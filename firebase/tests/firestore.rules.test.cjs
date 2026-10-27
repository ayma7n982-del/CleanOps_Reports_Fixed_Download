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
