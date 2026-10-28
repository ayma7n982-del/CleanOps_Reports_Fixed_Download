const {before, after, beforeEach, test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {initializeTestEnvironment, assertSucceeds, assertFails} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc, updateDoc, deleteDoc, Timestamp} = require('firebase/firestore');

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

