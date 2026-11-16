const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { deleteManagedAccount } = require('../lib/managed_user_deletion');
if (!process.env.FIREBASE_AUTH_EMULATOR_HOST || !process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error('Deletion tests must run with Auth and Firestore emulators.');
}
const app = initializeApp({ projectId: 'cleanops-user-deletion-test' });
const db = getFirestore(app), auth = getAuth(app);
let sequence = 0;
async function seed(role = 'worker', owner = 'owner') {
  const uid = `delete-test-${++sequence}`;
  await auth.createUser({ uid, email: `${uid}@example.invalid`, password: 'EmulatorOnly123!' });
  await db.collection('users').doc(uid).set({ name: 'Historical name', role,
    isActive: true, municipalityCoordinatorId: owner, groupId: 'g1' });
  return uid;
}
async function actor(id, role) { await db.collection('users').doc(id).set({ role, isActive: true }); }
after(async () => { await deleteApp(app); });

test('permanent deletion removes Auth, profile and active projections while preserving history; retry is idempotent', async () => {
  await actor('manager', 'donor_manager');
  const uid = await seed();
  for (const id of [uid, `${uid}-alias`]) await db.collection('operations').doc(id).set({
    _entity: 'worker', userId: uid, isActive: true, groupId: 'g1', name: 'Historical name',
  });
  await db.collection('users').doc(uid).collection('devices').doc('token').set({ token: 'emulator-token' });
  const attendance = { _entity: 'attendance', workerId: uid, workerName: 'Historical name', status: 'present' };
  const report = { _entity: 'report', reportKind: 'work_report', reportedBy: uid, reporterName: 'Historical name', status: 'approved', attendance: 19 };
  await db.collection('operations').doc(`${uid}-attendance`).set(attendance);
  await db.collection('operations').doc(`${uid}-report`).set(report);
  const result = await deleteManagedAccount(db, auth, 'manager', uid);
  assert.equal(result.ok, true);
  await assert.rejects(auth.getUser(uid), e => e.code === 'auth/user-not-found');
  assert.equal((await db.collection('users').doc(uid).get()).exists, false);
  assert.equal((await db.collection('users').doc(uid).collection('devices').get()).empty, true);
  for (const id of [uid, `${uid}-alias`]) assert.equal((await db.collection('operations').doc(id).get()).data().isDeleted, true);
  assert.deepEqual((await db.collection('operations').doc(`${uid}-attendance`).get()).data(), attendance);
  assert.deepEqual((await db.collection('operations').doc(`${uid}-report`).get()).data(), report);
  assert.equal((await deleteManagedAccount(db, auth, 'manager', uid)).alreadyAbsent, true);
  assert.equal((await db.collection('audit').where('targetId', '==', uid).get()).size, 1);
});

test('municipality cannot delete another municipality account or itself', async () => {
  await actor('owner', 'municipality_coordinator');
  const uid = await seed('group_supervisor', 'other-owner');
  await assert.rejects(deleteManagedAccount(db, auth, 'owner', uid), e => e.code === 'permission-denied');
  assert.equal((await auth.getUser(uid)).disabled, false);
  await assert.rejects(deleteManagedAccount(db, auth, 'owner', 'owner'), e => e.code === 'failed-precondition');
});

test('old soft-deleted accounts are permanently removed by their coordinator', async () => {
  const uid = await seed();
  await db.collection('users').doc(uid).update({ status: 'deleted', isActive: false });
  assert.equal((await deleteManagedAccount(db, auth, 'owner', uid)).ok, true);
  await assert.rejects(auth.getUser(uid), e => e.code === 'auth/user-not-found');
});

test('manager can clean orphaned Auth accounts and profiles with missing Auth', async () => {
  const orphan = await seed();
  await db.collection('users').doc(orphan).delete();
  assert.equal((await deleteManagedAccount(db, auth, 'manager', orphan)).ok, true);
  const profileOnly = await seed();
  await auth.deleteUser(profileOnly);
  assert.equal((await deleteManagedAccount(db, auth, 'owner', profileOnly)).ok, true);
});

test('failure never reports success and the same job can be completed by retry', async () => {
  const uid = await seed();
  const failing = new Proxy(auth, { get(target, key) {
    if (key === 'deleteUser') return async () => { throw new Error('simulated transient failure'); };
    const value = target[key]; return typeof value === 'function' ? value.bind(target) : value;
  }});
  await assert.rejects(deleteManagedAccount(db, failing, 'owner', uid), /simulated/);
  assert.equal((await db.collection('account_deletions').doc(uid).get()).data().status, 'pending');
  assert.equal((await db.collection('users').doc(uid).get()).data().isActive, false);
  assert.equal((await db.collection('audit').doc(`permanent-delete-${uid}`).get()).exists, false);
  assert.equal((await deleteManagedAccount(db, auth, 'owner', uid)).ok, true);
});

test('inactive managers and unsupported roles cannot delete accounts', async () => {
  const uid = await seed();
  await actor('council', 'jsc_coordinator');
  await assert.rejects(deleteManagedAccount(db, auth, 'council', uid), e => e.code === 'permission-denied');
  await db.collection('users').doc('inactive-manager').set({ role:'donor_manager', isActive:false });
  await assert.rejects(deleteManagedAccount(db, auth, 'inactive-manager', uid), e => e.code === 'permission-denied');
});
