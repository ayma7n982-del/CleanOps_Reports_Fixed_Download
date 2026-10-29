const {before, after, beforeEach, test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, deleteDoc, writeBatch, Timestamp, serverTimestamp, collection, query, where, getDocs, collectionGroup} = require('firebase/firestore');

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


test('message receipt is private to recipient and visible to sender', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'messages','msg-1'), message('head-a','group-a'));
  });
  const path = ['messages','msg-1','receipts','worker-a'];
  await assertSucceeds(setDoc(doc(db('worker-a'),...path), {
    userId:'worker-a', status:'read', updatedAt:serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(db('worker-a'),...path)));
  await assertSucceeds(getDoc(doc(db('head-a'),...path)));
  await assertSucceeds(getDocs(collection(db('head-a'),'messages','msg-1','receipts')));
  await assertFails(getDoc(doc(db('worker-b'),...path)));
  await assertFails(getDoc(doc(db('head-b'),...path)));
});

test('message receipt can be acknowledged but never forged, downgraded or deleted', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'messages','msg-1'), message('head-a','group-a'));
  });
  const own = doc(db('worker-a'),'messages','msg-1','receipts','worker-a');
  await assertFails(setDoc(doc(db('worker-b'),'messages','msg-1','receipts','worker-a'), {
    userId:'worker-a', status:'read', updatedAt:serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db('worker-b'),'messages','msg-1','receipts','worker-b'), {
    userId:'worker-b', status:'read', updatedAt:serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db('worker-a'),'messages','msg-1','receipts','worker-b'), {
    userId:'worker-a', status:'read', updatedAt:serverTimestamp(),
  }));
  await assertSucceeds(setDoc(own, {
    userId:'worker-a', status:'read', updatedAt:serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(own, {
    status:'acknowledged', updatedAt:serverTimestamp(),
  }));
  await assertFails(updateDoc(own, {status:'read', updatedAt:serverTimestamp()}));
  await assertFails(deleteDoc(own));
});

test('coordinator can acknowledge municipality broadcast but not read group receipt', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'messages','msg-1'), message('jsc','__ALL_MUNICIPALITIES__'));
  });
  await assertSucceeds(setDoc(doc(db('coordinator'),'messages','msg-1','receipts','coordinator'), {
    userId:'coordinator', status:'acknowledged', updatedAt:serverTimestamp(),
  }));
  await assertFails(setDoc(doc(db('worker-a'),'messages','msg-1','receipts','worker-a'), {
    userId:'worker-a', status:'read', updatedAt:serverTimestamp(),
  }));
});

test('queries for sent and own group messages respect message list rules', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'messages','msg-1'), message('head-a','group-a'));
  });
  await assertSucceeds(getDocs(query(collection(db('head-a'),'messages'),where('senderId','==','head-a'))));
  await assertSucceeds(getDocs(query(collection(db('worker-a'),'messages'),where('targetGroupId','==','group-a'))));
  await assertFails(getDocs(query(collection(db('worker-b'),'messages'),where('targetGroupId','==','group-a'))));
});


test('L2 direct message reaches only its managed workforce', async () => {
  await assertSucceeds(setDoc(doc(db('coordinator'),'messages','msg-1'), {
    ...message('coordinator','__USER__:worker-a'),
    targetUserId:'worker-a',
  }));
  await assertFails(setDoc(doc(db('head-a'),'messages','bad-spoof'), {
    ...message('head-a','__USER__:worker-b'),
    targetUserId:'worker-b',messageId:'bad-spoof',
  }));
});

test('direct messages require target ID and routing string to agree', async () => {
  await assertFails(setDoc(doc(db('coordinator'),'messages','msg-1'), {
    ...message('coordinator','__USER__:worker-b'),
    targetUserId:'worker-a',
  }));
});

test('L3 can write to active municipal coordinators but not workers', async () => {
  await assertSucceeds(setDoc(doc(db('jsc'),'messages','msg-1'), {
    ...message('jsc','__USER__:coordinator'),
    targetUserId:'coordinator',
  }));
  await assertFails(setDoc(doc(db('jsc'),'messages','second'), {
    ...message('jsc','__USER__:worker-b'),
    targetUserId:'worker-b',messageId:'second',
  }));
});

test('worker alert to linked coordinator is permitted, unrelated users denied', async () => {
  await assertSucceeds(setDoc(doc(db('worker-a'),'messages','msg-1'), {
    ...message('worker-a','__USER__:coordinator','emergency'),
    targetUserId:'coordinator',
  }));
  await assertFails(setDoc(doc(db('worker-a'),'messages','invalid'), {
    ...message('worker-a','__USER__:jsc','emergency'),
    targetUserId:'jsc',messageId:'invalid',
  }));
});


test('message attachments: sender may publish valid metadata, recipients may read', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'messages','msg-1'), message('head-a','group-a'));
  });
  const attachmentId = 'image-a';
  const path = ['messages','msg-1','attachments',attachmentId];
  await assertSucceeds(setDoc(doc(db('head-a'),...path), {
    attachmentId, path: 'message_attachments/msg-1/image-a.jpg',
    contentType:'image/jpeg', sizeBytes:102400, senderId:'head-a',
    createdAt:serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(db('worker-a'),...path)));
  await assertSucceeds(getDocs(collection(db('worker-a'),'messages','msg-1','attachments')));
  await assertFails(getDoc(doc(db('worker-b'),...path)));
  await assertFails(setDoc(doc(db('worker-a'),'messages','msg-1','attachments','evil'), {
    attachmentId:'evil', path:'message_attachments/msg-1/evil.jpg',
    contentType:'image/jpeg', sizeBytes:10, senderId:'worker-a',
    createdAt:serverTimestamp(),
  }));
  await assertFails(deleteDoc(doc(db('head-a'),...path)));
});

test('external SMS audit is readable only by sender or recipient and never writable by client', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'external_messages','sms-a'), {
      senderId:'coordinator', targetUserId:'worker-a',
      content:'Testing', channel:'sms', status:'submitted',
    });
  });
  await assertSucceeds(getDoc(doc(db('coordinator'),'external_messages','sms-a')));
  await assertSucceeds(getDoc(doc(db('worker-a'),'external_messages','sms-a')));
  await assertFails(getDoc(doc(db('worker-b'),'external_messages','sms-a')));
  await assertFails(setDoc(doc(db('coordinator'),'external_messages','sms-b'), {
    senderId:'coordinator',targetUserId:'worker-a',content:'Spoofed',
  }));
  await assertFails(updateDoc(doc(db('coordinator'),'external_messages','sms-a'), {status:'delivered'}));
});


test('reply metadata is accepted only for a readable parent message', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'messages','original'), {
      ...message('head-a','__USER__:coordinator'), messageId:'original',
    });
    await setDoc(doc(ctx.firestore(),'messages','hidden'), {
      ...message('head-b','group-b'), messageId:'hidden',
    });
  });
  await assertSucceeds(setDoc(doc(db('coordinator'),'messages','reply'), {
    ...message('coordinator','__USER__:head-a'), messageId:'reply',
    targetUserId:'head-a',replyToMessageId:'original',
  }));
  await assertFails(setDoc(doc(db('coordinator'),'messages','bad-reply'), {
    ...message('coordinator','__USER__:head-a'), messageId:'bad-reply',
    targetUserId:'head-a',replyToMessageId:'hidden',
  }));
});

test('scheduled message audit is visible only to sender and cannot be forged', async () => {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'scheduled_messages','coordinator_request'), {
      senderId:'coordinator', targetGroupId:'group-a', type:'info',
      content:'Future task',status:'scheduled', scheduledAt:Timestamp.now(),
    });
  });
  await assertSucceeds(getDoc(doc(db('coordinator'),'scheduled_messages','coordinator_request')));
  await assertFails(getDoc(doc(db('worker-a'),'scheduled_messages','coordinator_request')));
  await assertFails(setDoc(doc(db('coordinator'),'scheduled_messages','fake'), {
    senderId:'coordinator',content:'Spoofed', status:'scheduled',
  }));
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

const seedDecisionGroup = async () => env.withSecurityRulesDisabled(async ctx => {
  const store = ctx.firestore();
  await setDoc(doc(store,'operations','group-a'), {_entity:'group',municipalityCoordinatorId:'coordinator',
    isActive:true,adjacentGroupIds:['group-b']});
  await setDoc(doc(store,'operations','group-b'), {_entity:'group',municipalityCoordinatorId:'other'});
  for (const [id,name] of [['coordinator','Municipality'],['jsc','Council'],['manager','Manager']]) {
    await updateDoc(doc(store,'users',id), {name});
  }
});
const decision = (actor='coordinator', groupId='group-a', kind='ppe') => ({
  id:'decision-1',kind,title:'Urgent directive',body:'Provide safety equipment to the group',
  groupId,municipalityCoordinatorId:'coordinator',targetId:'',
  scopeKey:'municipality:coordinator',status:'issued',priority:'urgent',
  shiftDate:'2026-10-29',expiresAt:Timestamp.fromMillis(Date.now()+3600000),
  details:{},createdBy:actor,coordinatorName:actor==='coordinator'?'Municipality':
    actor==='jsc'?'Council':'Manager',createdAt:serverTimestamp(),schemaVersion:1,
});
test('decision hub: all L2-L4 roles issue real scoped directives', async () => {
  await seedDecisionGroup();
  for (const actor of ['coordinator','jsc','manager']) {
    await assertSucceeds(setDoc(doc(db(actor),'strategic_decisions', 'decision-1'), decision(actor)));
    await env.withSecurityRulesDisabled(async ctx =>
      deleteDoc(doc(ctx.firestore(),'strategic_decisions','decision-1')));
  }
});
test('decision hub: foreign municipality, inactive accounts and forged actor denied', async () => {
  await seedDecisionGroup();
  await assertFails(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),
    {...decision(),groupId:'group-b',municipalityCoordinatorId:'other'}));
  await assertFails(setDoc(doc(db('head-a'),'strategic_decisions','decision-1'),decision('head-a')));
  await assertFails(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),
    {...decision(),createdBy:'manager'}));
  await env.withSecurityRulesDisabled(async ctx =>
    updateDoc(doc(ctx.firestore(),'users','coordinator'),{isActive:false}));
  await assertFails(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),decision()));
});
test('decision hub: supervisor reads own directive and follows acknowledgement then completion', async () => {
  await seedDecisionGroup();
  await assertSucceeds(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),decision()));
  const ref=doc(db('head-a'),'strategic_decisions','decision-1');
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(getDocs(query(collection(db('head-a'),'strategic_decisions'),
    where('groupId','==','group-a'))));
  await assertFails(getDoc(doc(db('head-b'),'strategic_decisions','decision-1')));
  await assertFails(updateDoc(ref,{status:'completed',completedBy:'head-a',
    completedAt:serverTimestamp(),completionNote:'Completed without acknowledgement'}));
  await assertSucceeds(updateDoc(ref,{status:'acknowledged',
    acknowledgedBy:'head-a',acknowledgedAt:serverTimestamp()}));
  await assertFails(updateDoc(ref,{status:'completed',completedBy:'head-a',
    completedAt:serverTimestamp(),completionNote:'short'}));
  await assertSucceeds(updateDoc(ref,{status:'completed',completedBy:'head-a',
    completedAt:serverTimestamp(),completionNote:'Safety equipment received and recorded.'}));
  await assertFails(updateDoc(ref,{body:'forged'}));
  await assertFails(deleteDoc(ref));
});
test('decision hub: global broadcasts restricted to L3/L4 and visible on supervisor dashboards', async () => {
  await seedDecisionGroup();
  const broadcast={...decision('jsc','','broadcast'),municipalityCoordinatorId:'',
    scopeKey:'global'};
  await assertFails(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),
    {...broadcast,createdBy:'coordinator',coordinatorName:'Municipality'}));
  await assertSucceeds(setDoc(doc(db('jsc'),'strategic_decisions','decision-1'),broadcast));
  await assertSucceeds(getDocs(query(collection(db('head-b'),'strategic_decisions'),
    where('scopeKey','==','global'), where('kind','==','broadcast'))));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),
    'strategic_decisions','decision-1')));
});
test('decision hub: container dispatch must reference a truly full own-group container', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(),'containers','c1'),
    {groupId:'group-a',municipalityId:'coordinator',status:'empty'}));
  const action={...decision('coordinator','group-a','collection'),details:{containerId:'c1'}};
  await assertFails(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),action));
  await env.withSecurityRulesDisabled(async ctx => updateDoc(doc(ctx.firestore(),'containers','c1'),
    {status:'full'}));
  await assertSucceeds(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),action));
});
test('decision hub: health hazard requires a real fullSince older than 12 hours', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(),'containers','c1'),
    {groupId:'group-a',municipalityId:'coordinator',status:'full',updatedAt:Timestamp.fromMillis(0)}));
  const action={...decision('coordinator','group-a','health'),details:{containerId:'c1'}};
  await assertFails(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),action));
  await env.withSecurityRulesDisabled(async ctx => updateDoc(doc(ctx.firestore(),'containers','c1'),
    {fullSince:Timestamp.fromMillis(Date.now()-13*3600000)}));
  await assertSucceeds(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),action));
});
test('decision hub: redirects reject a full alternative and accept a safe active alternative', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'dumpsites','source'),{nameAr:'Source',isActive:true,fillPercentage:90,capacity:100});
    await setDoc(doc(ctx.firestore(),'dumpsites','alternate'),{nameAr:'Alternate',isActive:true,fillPercentage:90,capacity:100});
  });
  const action={...decision('coordinator','group-a','dumpsite_redirect'),
    details:{sourceId:'source',sourceName:'Source',alternativeId:'alternate',
      alternativeName:'Alternate',requestLeveling:true}};
  await assertFails(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),action));
  await env.withSecurityRulesDisabled(async ctx =>
    updateDoc(doc(ctx.firestore(),'dumpsites','alternate'),{fillPercentage:20}));
  await assertSucceeds(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),action));
});
test('decision hub: complete status transition and immutable history commit atomically', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx =>
    setDoc(doc(ctx.firestore(),'containers','c1'),{id:'c1',status:'empty',
      issueStatus:'none',groupId:'group-a',municipalityId:'coordinator',updatedBy:'head-a'}));
  const store=db('head-a'), batch=writeBatch(store);
  batch.update(doc(store,'containers','c1'), {status:'full',fullSince:serverTimestamp(),
    lastStatusEventId:'e1',updatedBy:'head-a',updatedAt:serverTimestamp()});
  batch.set(doc(store,'containers','c1','status_events','e1'),{
    containerId:'c1',status:'full',previousStatus:'empty',groupId:'group-a',
    municipalityId:'coordinator',createdBy:'head-a',at:serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  await assertSucceeds(getDocs(query(collectionGroup(db('coordinator'),'status_events'),
    where('municipalityId','==','coordinator'))));
  await assertFails(updateDoc(doc(store,'containers','c1','status_events','e1'),{status:'empty'}));
});
test('decision hub: a bare forged fullSince write is denied', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx =>
    setDoc(doc(ctx.firestore(),'containers','c1'),{id:'c1',status:'empty',
      issueStatus:'none',groupId:'group-a',municipalityId:'coordinator',updatedBy:'head-a'}));
  await assertFails(updateDoc(doc(db('head-a'),'containers','c1'),{
    status:'full',fullSince:Timestamp.fromMillis(0),updatedBy:'head-a',lastStatusEventId:'fake'}));
});
test('decision hub: plans are manager-only immutable and municipality-scoped', async () => {
  await seedDecisionGroup();
  const plan={id:'plan',targetCycleId:'12',status:'approved',
    municipalityCoordinatorId:'coordinator',decisionIds:['decision-1'],
    recommendations:[{decisionId:'decision-1'}],sourceCycleId:'11',
    createdBy:'coordinator',coordinatorName:'Municipality',createdAt:serverTimestamp(),
    schemaVersion:1};
  await assertFails(setDoc(doc(db('head-a'),'strategic_plans','plan'),plan));
  await assertSucceeds(setDoc(doc(db('coordinator'),'strategic_plans','plan'),plan));
  await assertFails(updateDoc(doc(db('coordinator'),'strategic_plans','plan'),{status:'changed'}));
});

test('decision hub: own-group status retry can read missing or existing event id only', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx =>
    setDoc(doc(ctx.firestore(),'containers','c1'),{id:'c1',status:'empty',
      issueStatus:'none',groupId:'group-a',municipalityId:'coordinator',updatedBy:'head-a'}));
  await assertSucceeds(getDoc(doc(db('head-a'),'containers','c1','status_events','missing')));
  await assertFails(getDoc(doc(db('head-b'),'containers','c1','status_events','missing')));
});

test('decision hub: reserve assignment is atomic, named and cannot be double booked', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(),'operations','reserve'),{
      _entity:'worker',name:'Reserve Worker',job:'collector',isReserve:true,
      municipalityCoordinatorId:'coordinator',isActive:true,
    });
    await setDoc(doc(ctx.firestore(),'operations','group-c'),{
      _entity:'group',municipalityCoordinatorId:'coordinator',isActive:true,
    });
  });
  const assign=(id,groupId)=>({...decision('coordinator',groupId,'temporary_coverage'),id,
    details:{assignmentType:'worker',assignmentId:'reserve',assignmentLockId:'reserve',
      workerName:'Reserve Worker',workerJob:'collector'}});
  const store=db('coordinator');
  const a=assign('reserve-decision','group-a');
  await assertFails(setDoc(doc(store,'strategic_decisions',a.id),a));
  const batch=writeBatch(store);
  batch.set(doc(store,'strategic_decisions',a.id),a);
  batch.set(doc(store,'temporary_assignments','reserve'),{
    decisionId:a.id,workerId:'reserve',groupId:'group-a',
    municipalityCoordinatorId:'coordinator',validUntil:a.expiresAt,
    createdBy:'coordinator',createdAt:serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
  const b=assign('second-assignment','group-c'), duplicate=writeBatch(store);
  duplicate.set(doc(store,'strategic_decisions',b.id),b);
  duplicate.set(doc(store,'temporary_assignments','reserve'),{
    decisionId:b.id,workerId:'reserve',groupId:'group-c',
    municipalityCoordinatorId:'coordinator',validUntil:b.expiresAt,
    createdBy:'coordinator',createdAt:serverTimestamp(),
  });
  await assertFails(duplicate.commit());
});
test('decision hub: adjacent coverage notifies both groups without widening access', async () => {
  await seedDecisionGroup();
  await env.withSecurityRulesDisabled(async ctx => updateDoc(doc(ctx.firestore(),'operations','group-b'),
    {municipalityCoordinatorId:'coordinator'}));
  const action={...decision('coordinator','group-a','temporary_coverage'),
    additionalGroupId:'group-b',details:{assignmentType:'group',assignmentId:'group-b'}};
  await assertSucceeds(setDoc(doc(db('coordinator'),'strategic_decisions','decision-1'),action));
  await assertSucceeds(getDocs(query(collection(db('head-b'),'strategic_decisions'),
    where('additionalGroupId','==','group-b'),where('kind','==','temporary_coverage'))));
});
