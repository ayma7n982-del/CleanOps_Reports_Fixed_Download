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
