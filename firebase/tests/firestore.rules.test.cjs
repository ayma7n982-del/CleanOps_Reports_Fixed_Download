const {before, after, beforeEach, test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, Timestamp} = require('firebase/firestore');

let env;
const projectId = 'cleanops-messaging-rules-test';
const rules = fs.readFileSync(require('node:path').join(__dirname, '..', 'firestore.rules'), 'utf8');

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {rules, host: '127.0.0.1', port: 8080},
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [id, role, groupId, active] of [
      ['head-a', 'group_supervisor', 'group-a', true],
      ['head-b', 'group_supervisor', 'group-b', true],
      ['worker-a', 'worker', 'group-a', true],
      ['worker-b', 'worker', 'group-b', true],
      ['inactive-head', 'group_supervisor', 'group-a', false],
      ['coordinator', 'municipality_coordinator', null, true],
      ['jsc', 'jsc_coordinator', null, true],
      ['manager', 'donor_manager', null, true],
    ]) {
      await setDoc(doc(db, 'users', id), {
        role, groupId, isActive: active, municipalityCoordinatorId: 'coordinator',
      });
    }
  });
});
const db = (uid) => env.authenticatedContext(uid).firestore();
const message = (senderId, targetGroupId, type='info') => ({
  messageId: 'msg-1', senderId, targetGroupId, type,
  content: 'Operational message', timestamp: Timestamp.now(), isRead: false,
});

test('supervisor sends to own group', async () => {
  await assertSucceeds(setDoc(doc(db('head-a'), 'messages', 'msg-1'), message('head-a','group-a')));
});
test('supervisor cannot send to another group', async () => {
  await assertFails(setDoc(doc(db('head-a'), 'messages', 'msg-1'), message('head-a','group-b')));
});
test('supervisor cannot spoof sender', async () => {
  await assertFails(setDoc(doc(db('head-a'), 'messages', 'msg-1'), message('head-b','group-a')));
});
test('inactive supervisor cannot send', async () => {
  await assertFails(setDoc(doc(db('inactive-head'), 'messages', 'msg-1'), message('inactive-head','group-a')));
});
test('worker in same group can read; other group cannot', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'messages','msg-1'), message('head-a','group-a'));
  });
  await assertSucceeds(getDoc(doc(db('worker-a'),'messages','msg-1')));
  await assertFails(getDoc(doc(db('worker-b'),'messages','msg-1')));
});
test('supervisor cannot change message content or delete', async () => {
  await assertSucceeds(setDoc(doc(db('head-a'),'messages','msg-1'), message('head-a','group-a')));
  await assertFails(updateDoc(doc(db('head-a'),'messages','msg-1'), {content:'changed'}));
  await assertFails(deleteDoc(doc(db('head-a'),'messages','msg-1')));
});
test('unauthenticated users cannot read messages', async () => {
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'messages','msg-1')));
});

test('supervisor warning broadcast is rejected', async () => {
  await assertFails(setDoc(doc(db('head-a'),'messages','msg-1'), message('head-a','group-a','warning')));
});
test('worker cannot send messages to council', async () => {
  await assertFails(setDoc(doc(db('worker-a'),'messages','msg-1'), message('worker-a','__JSC__','info')));
});
test('supervisor may escalate a message to council', async () => {
  await assertSucceeds(setDoc(doc(db('head-a'),'messages','msg-1'), message('head-a','__JSC__','warning')));
});
test('inactive worker cannot read group messages', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'users','worker-a'), {role:'worker',groupId:'group-a',isActive:false});
    await setDoc(doc(ctx.firestore(),'messages','msg-1'), message('head-a','group-a'));
  });
  await assertFails(getDoc(doc(db('worker-a'),'messages','msg-1')));
});

test('operations: active workforce can read own group but not another group', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    const admin = ctx.firestore();
    await setDoc(doc(admin,'operations','trip-a'), {_entity:'trip',groupId:'group-a',reportedBy:'head-a'});
    await setDoc(doc(admin,'operations','trip-b'), {_entity:'trip',groupId:'group-b',reportedBy:'head-b'});
  });
  await assertSucceeds(getDoc(doc(db('worker-a'),'operations','trip-a')));
  await assertFails(getDoc(doc(db('worker-a'),'operations','trip-b')));
  await assertSucceeds(getDoc(doc(db('head-a'),'operations','trip-a')));
  await assertFails(getDoc(doc(db('head-a'),'operations','trip-b')));
});

test('operations: direct target is readable only by the targeted workforce user', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'operations','direct-worker-a'), {
      _entity:'notification', targetUserId:'worker-a'
    });
  });
  await assertSucceeds(getDoc(doc(db('worker-a'),'operations','direct-worker-a')));
  await assertFails(getDoc(doc(db('worker-b'),'operations','direct-worker-a')));
});

test('operations: inactive workforce and anonymous users are rejected', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'operations','trip-a'), {_entity:'trip',groupId:'group-a'});
  });
  await assertFails(getDoc(doc(db('inactive-head'),'operations','trip-a')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'operations','trip-a')));
});

test('dumpsites: workforce cannot read management dumpsites', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'dumpsites','dump-a'), {
      nameAr:'مكب أ', nameEn:'Dump A', capacity:100,
      fillPercentage:50, isActive:true
    });
  });
  await assertFails(getDoc(doc(db('worker-a'),'dumpsites','dump-a')));
  await assertFails(getDoc(doc(db('head-a'),'dumpsites','dump-a')));
  await assertSucceeds(getDoc(doc(db('coordinator'),'dumpsites','dump-a')));
  await assertSucceeds(getDoc(doc(db('jsc'),'dumpsites','dump-a')));
  await assertSucceeds(getDoc(doc(db('manager'),'dumpsites','dump-a')));
});

test('operations: management roles retain operational oversight', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'operations','trip-b'), {_entity:'trip',groupId:'group-b'});
  });
  for (const uid of ['coordinator','jsc','manager']) {
    await assertSucceeds(getDoc(doc(db(uid),'operations','trip-b')));
  }
});


test('operations: supervisor creates trips only for own group and identity', async () => {
  const ownTrip = {
    _entity:'trip', groupId:'group-a', supervisorId:'head-a',
    status:'in_progress', createdAt:'2026-10-28T08:00:00.000Z',
  };
  await assertSucceeds(setDoc(doc(db('head-a'),'operations','trip-own-create'), ownTrip));
  await assertFails(setDoc(doc(db('head-a'),'operations','trip-other-create'), {
    ...ownTrip, groupId:'group-b',
  }));
  await assertFails(setDoc(doc(db('head-a'),'operations','trip-spoof-create'), {
    ...ownTrip, supervisorId:'head-b',
  }));
});

test('operations: supervisor may complete own-group trip but cannot mutate or close another group', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    const admin = ctx.firestore();
    await setDoc(doc(admin,'operations','trip-own-update'), {
      _entity:'trip', groupId:'group-a', supervisorId:'head-a',
      status:'in_progress', createdAt:'2026-10-28T08:00:00.000Z',
    });
    await setDoc(doc(admin,'operations','trip-other-update'), {
      _entity:'trip', groupId:'group-b', supervisorId:'head-b',
      status:'in_progress', createdAt:'2026-10-28T08:00:00.000Z',
    });
  });
  await assertSucceeds(updateDoc(doc(db('head-a'),'operations','trip-own-update'), {
    status:'completed', completedBy:'head-a',
    completedAt:'2026-10-28T09:00:00.000Z',
  }));
  await assertFails(updateDoc(doc(db('head-a'),'operations','trip-other-update'), {
    status:'completed', completedBy:'head-a',
    completedAt:'2026-10-28T09:00:00.000Z',
  }));
  await assertFails(updateDoc(doc(db('head-a'),'operations','trip-own-update'), {
    landfill:'unauthorized-change',
  }));
});

test('cart redirect: L2 atomically reassigns owned equipment with matching audit log', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    const admin = ctx.firestore();
    await setDoc(doc(admin,'operations','group-a'), {_entity:'group',municipalityCoordinatorId:'coordinator'});
    await setDoc(doc(admin,'operations','group-b'), {_entity:'group',municipalityCoordinatorId:'coordinator'});
    await setDoc(doc(admin,'equipment','cart-a'), {
      id:'cart-a', type:'cart', category:'cart',
      municipalityCoordinatorId:'coordinator', groupId:'group-a', isDeleted:false,
    });
  });

  const coordinatorDb = db('coordinator');
  const batch = writeBatch(coordinatorDb);
  batch.update(doc(coordinatorDb,'equipment','cart-a'), {
    groupId:'group-b', updatedBy:'coordinator',
    updatedAt:'2026-10-28T09:00:00.000Z',
    lastRedirectRequestId:'redirect-a',
  });
  batch.set(doc(coordinatorDb,'operations','redirect-a'), {
    id:'redirect-a', _entity:'cart_redirect',
    municipalityCoordinatorId:'coordinator', requestedBy:'coordinator',
    fromGroupId:'group-a', toGroupId:'group-b',
    cartId:'cart-a', cartEntity:'equipment', cartCollection:'equipment',
    status:'applied',
  });
  await assertSucceeds(batch.commit());

  await assertFails(updateDoc(doc(coordinatorDb,'equipment','cart-a'), {
    groupId:'group-a', updatedBy:'coordinator',
    updatedAt:'2026-10-28T09:05:00.000Z',
    lastRedirectRequestId:'missing-log',
  }));
  await assertFails(updateDoc(doc(db('head-a'),'equipment','cart-a'), {
    groupId:'group-a',
  }));
});

test('user deletion: managed account is disabled only with an atomic authorized deletion request', async () => {
  const coordinatorDb = db('coordinator');
  const batch = writeBatch(coordinatorDb);
  batch.update(doc(coordinatorDb,'users','worker-a'), {
    isActive:false,
    status:'pending_deletion',
    deletionRequestedBy:'coordinator',
    deletionRequestedAt:'2026-10-28T09:10:00.000Z',
    deletionRequestId:'delete-worker-a',
    updatedBy:'coordinator',
    updatedAt:'2026-10-28T09:10:00.000Z',
  });
  batch.set(doc(coordinatorDb,'admin_requests','delete-worker-a'), {
    id:'delete-worker-a',
    type:'delete_user',
    targetUserId:'worker-a',
    requestedBy:'coordinator',
    status:'pending',
    createdAt:'2026-10-28T09:10:00.000Z',
  });
  await assertSucceeds(batch.commit());

  await assertFails(updateDoc(doc(db('head-a'),'users','worker-b'), {
    isActive:false,
    status:'pending_deletion',
  }));
  await assertFails(setDoc(doc(db('head-a'),'admin_requests','bad-delete'), {
    id:'bad-delete', type:'delete_user',
    targetUserId:'worker-b', requestedBy:'head-a', status:'pending',
  }));
});



test('JSC dispatch atomically marks a real machine with a matching request', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'equipment', 'machine-a'), {
      id:'machine-a', type:'loader', status:'available',
      municipalityCoordinatorId:'coordinator', groupId:'group-a', isDeleted:false,
    });
  });
  const jscDb = db('jsc');
  const batch = writeBatch(jscDb);
  batch.update(doc(jscDb, 'equipment', 'machine-a'), {
    dispatchStatus:'dispatched', dispatchMunicipality:'دير البلح',
    dispatchRequestId:'dispatch-a', dispatchBy:'jsc',
    dispatchAt:'2026-10-28T09:00:00.000Z',
  });
  batch.set(doc(jscDb, 'operations', 'dispatch-a'), {
    id:'dispatch-a', _entity:'equipment_dispatch', equipmentId:'machine-a',
    municipality:'دير البلح', requestedBy:'jsc', status:'applied',
  });
  await assertSucceeds(batch.commit());
  await assertFails(updateDoc(doc(jscDb, 'equipment', 'machine-a'), {
    groupId:'other-group',
  }));
  await assertFails(updateDoc(doc(db('coordinator'), 'equipment', 'machine-a'), {
    dispatchMunicipality:'رفح',
  }));
});

test('JSC cannot dispatch without an approved request or dispatch twice', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'equipment', 'machine-b'), {
      id:'machine-b', type:'loader', dispatchStatus:'dispatched',
      dispatchRequestId:'existing', dispatchMunicipality:'رفح',
      dispatchBy:'jsc', dispatchAt:'2026-10-28T09:00:00.000Z',
    });
  });
  await assertFails(updateDoc(doc(db('jsc'), 'equipment', 'machine-b'), {
    dispatchRequestId:'missing', dispatchMunicipality:'دير البلح',
  }));
  await assertFails(setDoc(doc(db('jsc'), 'operations', 'fake-dispatch'), {
    id:'fake-dispatch', _entity:'equipment_dispatch',
    equipmentId:'machine-b', municipality:'دير البلح',
    requestedBy:'jsc', status:'applied',
  }));
});


test('JSC can acknowledge and then close SOS; workforce cannot close', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'operations', 'sos-a'), {
      id:'sos-a', _entity:'emergency', status:'urgent',
      acknowledged:false, reportedBy:'head-a', groupId:'group-a',
      municipalityCoordinatorId:'coordinator',
    });
  });
  const jscDb = db('jsc');
  await assertSucceeds(updateDoc(doc(jscDb, 'operations', 'sos-a'), {
    status:'acknowledged', acknowledged:true,
    acknowledgedBy:'jsc', acknowledgedAt:'2026-10-28T09:00:00.000Z',
    updatedAt:'2026-10-28T09:00:00.000Z',
  }));
  await assertFails(updateDoc(doc(db('head-a'), 'operations', 'sos-a'), {
    status:'closed', closedBy:'head-a',
    closedAt:'2026-10-28T09:01:00.000Z', resolutionNote:'not authorized',
  }));
  await assertSucceeds(updateDoc(doc(jscDb, 'operations', 'sos-a'), {
    status:'closed', closedBy:'jsc',
    closedAt:'2026-10-28T09:02:00.000Z',
    resolutionNote:'handed over safely', updatedAt:'2026-10-28T09:02:00.000Z',
  }));
});

test('JSC referral is scoped and does not allow changing SOS location', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'operations', 'sos-b'), {
      id:'sos-b', _entity:'emergency', status:'urgent',
      acknowledged:false, latitude:31.5, longitude:34.4,
    });
  });
  const jscDb = db('jsc');
  await assertSucceeds(updateDoc(doc(jscDb,'operations','sos-b'), {
    referredBy:'jsc', referredAt:'2026-10-28T09:00:00.000Z',
    referralDestination:'هندسة المتفجرات',
    updatedAt:'2026-10-28T09:00:00.000Z',
  }));
  await assertFails(updateDoc(doc(jscDb,'operations','sos-b'), {
    latitude:31.4,
  }));
  await assertFails(updateDoc(doc(db('head-a'),'operations','sos-b'), {
    referredBy:'head-a',
  }));
});

test('only JSC can reopen an already secured and acknowledged SOS', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'operations','sos-secure'), {
      id:'sos-secure', _entity:'emergency', status:'secured', acknowledged:true,
      acknowledgedBy:'coordinator', acknowledgedAt:'2026-10-28T09:00:00.000Z',
    });
    await setDoc(doc(ctx.firestore(),'operations','sos-urgent'), {
      id:'sos-urgent', _entity:'emergency', status:'urgent', acknowledged:false,
    });
  });
  await assertFails(updateDoc(doc(db('jsc'),'operations','sos-urgent'), {
    status:'reopened', reopenedBy:'jsc', reopenedAt:'2026-10-28T09:10:00.000Z',
  }));
  await assertSucceeds(updateDoc(doc(db('jsc'),'operations','sos-secure'), {
    status:'reopened', reopenedBy:'jsc', reopenedAt:'2026-10-28T09:10:00.000Z',
    updatedAt:'2026-10-28T09:10:00.000Z',
  }));
});

// JSC return is a new operation, independent of the L2 cart redirect model.
test('JSC can atomically return a dispatched machine without changing its group', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'equipment', 'loader-return'), {
      id:'loader-return', type:'loader', municipalityCoordinatorId:'coordinator',
      groupId:'group-a', isDeleted:false, dispatchStatus:'dispatched',
      dispatchRequestId:'dispatch-source', dispatchBy:'jsc',
      dispatchMunicipality:'رفح',
    });
  });
  const jscDb = db('jsc');
  const batch = writeBatch(jscDb);
  batch.update(doc(jscDb,'equipment','loader-return'), {
    dispatchStatus:'available', lastReturnRequestId:'return-a',
    returnedBy:'jsc', returnedAt:'2026-10-28T12:00:00Z', returnNote:'Mission completed',
  });
  batch.set(doc(jscDb,'operations','return-a'), {
    id:'return-a', _entity:'equipment_return', equipmentId:'loader-return',
    sourceDispatchRequestId:'dispatch-source', requestedBy:'jsc',
    returnNote:'Mission completed', status:'applied',
  });
  await assertSucceeds(batch.commit());
  const saved = await getDoc(doc(jscDb,'equipment','loader-return'));
  assert.equal(saved.data().groupId, 'group-a');
  assert.equal(saved.data().dispatchStatus, 'available');
  await assertFails(updateDoc(doc(jscDb,'equipment','loader-return'), {
    groupId:'group-b',
  }));
});

test('JSC cannot return machine without a matching log or wrong source dispatch', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'equipment','loader-return-b'), {
      id:'loader-return-b', type:'loader', dispatchStatus:'dispatched',
      dispatchRequestId:'real-source', dispatchBy:'jsc',
    });
  });
  await assertFails(updateDoc(doc(db('jsc'),'equipment','loader-return-b'), {
    dispatchStatus:'available',lastReturnRequestId:'none',
    returnedBy:'jsc',returnedAt:'2026-10-28T12:00:00Z',
    returnNote:'Mission complete',
  }));
  await assertFails(setDoc(doc(db('jsc'),'operations','fake-return'), {
    id:'fake-return',_entity:'equipment_return',
    equipmentId:'loader-return-b',sourceDispatchRequestId:'wrong-source',
    requestedBy:'jsc',returnNote:'Mission complete',status:'applied',
  }));
});

// Specialist clearance is documented by JSC with a nonempty reference; this
// emulator test does not establish that an external authority actually signed it.
test('JSC can record specialist clearance only after acknowledged referral, then reopen and close', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'operations','sos-clear'), {
      id:'sos-clear', _entity:'emergency', status:'acknowledged',
      acknowledged:true, acknowledgedBy:'jsc', acknowledgedAt:'2026-10-28T10:00:00Z',
      referralDestination:'هندسة المتفجرات',
      referredBy:'jsc', referredAt:'2026-10-28T10:01:00Z',
      street:'شارع تجريبي',latitude:31.4,longitude:34.3,
    });
  });
  const jscDb = db('jsc');
  const record = doc(jscDb, 'operations','sos-clear');
  await assertFails(updateDoc(record, {
    status:'secured',securedBy:'jsc',securedAt:'2026-10-28T10:10:00Z',
    eodOfficer:'',eodReference:'',securityNote:'',
  }));
  await assertFails(updateDoc(doc(db('head-a'),'operations','sos-clear'), {
    status:'secured',securedBy:'head-a',securedAt:'2026-10-28T10:10:00Z',
    eodOfficer:'EOD',eodReference:'ref',securityNote:'ok',
  }));
  await assertSucceeds(updateDoc(record, {
    status:'secured',securedBy:'jsc',securedAt:'2026-10-28T10:11:00Z',
    eodOfficer:'EOD representative',eodReference:'EOD-2026-100',
    securityNote:'Specialist written clearance recorded',
    updatedAt:'2026-10-28T10:11:00Z',
  }));
  await assertSucceeds(updateDoc(record, {
    status:'reopened',reopenedBy:'jsc',reopenedAt:'2026-10-28T10:15:00Z',
    updatedAt:'2026-10-28T10:15:00Z',
  }));
  await assertSucceeds(updateDoc(record, {
    status:'closed',closedBy:'jsc',closedAt:'2026-10-28T10:30:00Z',
    resolutionNote:'Administrative closure after clearance',
    updatedAt:'2026-10-28T10:30:00Z',
  }));
  const saved = await getDoc(record);
  assert.equal(saved.data().status, 'closed');
  assert.equal(saved.data().latitude, 31.4);
});

test('a JSC user cannot declare unacknowledged or unreferred SOS secured', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'operations','sos-unreferred'), {
      id:'sos-unreferred',_entity:'emergency',status:'acknowledged',
      acknowledged:true,acknowledgedBy:'jsc',acknowledgedAt:'t',
    });
  });
  await assertFails(updateDoc(doc(db('jsc'),'operations','sos-unreferred'), {
    status:'secured',securedBy:'jsc',securedAt:'t',
    eodOfficer:'Specialist',eodReference:'EOD-123',
    securityNote:'Verification',updatedAt:'t',
  }));
});

test('JSC cannot dispatch or return a cart under the machine workflow', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'equipment','cart-blocked'), {
      id:'cart-blocked',type:'cart',category:'cart',status:'available',
      groupId:'group-a',municipalityCoordinatorId:'coordinator',isDeleted:false,
      dispatchStatus:'dispatched',dispatchRequestId:'cart-source',
    });
  });
  const jscDb = db('jsc');
  const returnBatch = writeBatch(jscDb);
  returnBatch.update(doc(jscDb,'equipment','cart-blocked'), {
    dispatchStatus:'available',lastReturnRequestId:'cart-return',
    returnedBy:'jsc',returnedAt:'t',returnNote:'No cart reassignment',
  });
  returnBatch.set(doc(jscDb,'operations','cart-return'), {
    id:'cart-return',_entity:'equipment_return',
    equipmentId:'cart-blocked',sourceDispatchRequestId:'cart-source',
    requestedBy:'jsc',returnNote:'No cart reassignment',status:'applied',
  });
  await assertFails(returnBatch.commit());
});

test('municipality may acknowledge only SOS assigned to its account', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'operations', 'municipal-sos'), {
      id:'municipal-sos', _entity:'emergency',
      status:'urgent', acknowledged:false, groupId:'group-a',
      municipalityCoordinatorId:'coordinator',
    });
    await setDoc(doc(ctx.firestore(), 'operations', 'foreign-sos'), {
      id:'foreign-sos', _entity:'emergency',
      status:'urgent', acknowledged:false, groupId:'group-b',
      municipalityCoordinatorId:'coordinator-other',
    });
  });
  await assertSucceeds(updateDoc(doc(db('coordinator'),'operations','municipal-sos'), {
    acknowledged:true, acknowledgedBy:'coordinator',
    acknowledgedAt:'2026-10-28T10:00:00Z',status:'acknowledged',
    updatedAt:'2026-10-28T10:00:00Z',
  }));
  await assertFails(updateDoc(doc(db('coordinator'),'operations','foreign-sos'), {
    acknowledged:true, acknowledgedBy:'coordinator',
    acknowledgedAt:'2026-10-28T10:00:00Z',status:'acknowledged',
    updatedAt:'2026-10-28T10:00:00Z',
  }));
});


test('L2 can deactivate only its active workforce without ending cycle', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    const admin = ctx.firestore();
    await setDoc(doc(admin,'users','worker-a'), {
      role:'worker',username:'worker-a',groupId:'group-a',
      municipalityCoordinatorId:'coordinator',isActive:true,status:'active',
      cycleId:'cycle-active',
    });
    await setDoc(doc(admin,'work_cycles','cycle-active'), {
      status:'active',
      startDate:Timestamp.fromDate(new Date(Date.now()-3600000)),
      endDate:Timestamp.fromDate(new Date(Date.now()+86400000)),
    });
  });
  await assertSucceeds(updateDoc(doc(db('coordinator'),'users','worker-a'), {
    isActive:false,status:'deactivated',
    deactivatedBy:'coordinator',deactivatedAt:Timestamp.now(),
    updatedAt:Timestamp.now(),
  }));
  await assertFails(updateDoc(doc(db('worker-a'),'users','worker-a'), {status:'active'}));
});

test('L2 cannot deactivate manager or a worker outside its municipality', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    const admin = ctx.firestore();
    await setDoc(doc(admin,'users','outsider'), {
      role:'worker',username:'outsider',groupId:'outside',
      municipalityCoordinatorId:'other-coordinator',isActive:true,status:'active',
    });
    await setDoc(doc(admin,'users','manager'), {
      role:'donor_manager',username:'manager',isActive:true,status:'active',
    });
  });
  const change = {isActive:false,status:'deactivated',
    deactivatedBy:'coordinator',deactivatedAt:Timestamp.now()};
  await assertFails(updateDoc(doc(db('coordinator'),'users','outsider'), change));
  await assertFails(updateDoc(doc(db('coordinator'),'users','manager'), change));
});

test('L2 cannot freeze a worker before cycle end or bypass changed-field limits', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    const admin = ctx.firestore();
    await setDoc(doc(admin,'users','worker-a'), {
      role:'worker',username:'worker-a',groupId:'group-a',
      municipalityCoordinatorId:'coordinator',isActive:true,status:'active',
      cycleId:'cycle-active',
    });
    await setDoc(doc(admin,'work_cycles','cycle-active'), {
      status:'active',startDate:Timestamp.fromDate(new Date(Date.now()-3600000)),
      endDate:Timestamp.fromDate(new Date(Date.now()+86400000)),
    });
  });
  await assertFails(updateDoc(doc(db('coordinator'),'users','worker-a'), {
    isActive:false,status:'frozen',frozenBy:'coordinator',frozenAt:Timestamp.now(),
  }));
  await assertFails(updateDoc(doc(db('coordinator'),'users','worker-a'), {
    isActive:false,status:'deactivated',deactivatedBy:'coordinator',role:'donor_manager',
  }));
});



test('supervisor creates own-group geolocated SOS; foreign group and missing GPS denied', async () => {
  const sos = {
    id:'new-sos',_entity:'emergency',groupId:'group-a',
    reportedBy:'head-a',userId:'head-a',status:'urgent',
    acknowledged:false,latitude:31.9,longitude:35.2,street:'Test site',
    createdAt:new Date().toISOString(),isDeleted:false,
  };
  await assertSucceeds(setDoc(doc(db('head-a'),'operations','new-sos'),sos));
  await assertFails(setDoc(doc(db('head-a'),'operations','foreign-sos-create'),{
    ...sos,id:'foreign-sos-create',groupId:'group-b',
  }));
  await assertFails(setDoc(doc(db('head-a'),'operations','sos-without-gps'),{
    ...sos,id:'sos-without-gps',latitude:null,
  }));
  await assertFails(setDoc(doc(db('worker-a'),'operations','worker-fake-sos'),{
    ...sos,id:'worker-fake-sos',reportedBy:'worker-a',userId:'worker-a',
  }));
});
