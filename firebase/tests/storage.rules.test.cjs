const {before, after, beforeEach, test} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {initializeTestEnvironment, assertSucceeds, assertFails} =
  require('@firebase/rules-unit-testing');
const {doc, setDoc, Timestamp} = require('firebase/firestore');
const {ref, uploadBytes, getBytes, deleteObject} = require('firebase/storage');

let env;
const projectId = 'cleanops-messaging-storage-test';
const bucket = `gs://${projectId}.appspot.com`;

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1', port: 8080,
      rules: fs.readFileSync(path.join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
    storage: {
      host: '127.0.0.1', port: 9199,
      rules: fs.readFileSync(path.join(__dirname, '..', 'storage.rules'), 'utf8'),
    },
  });
});
after(async () => { if (env) await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async ctx => {
    const db = ctx.firestore();
    for (const [id, role, groupId] of [
      ['head-a', 'group_supervisor', 'group-a'],
      ['worker-a', 'worker', 'group-a'],
      ['worker-b', 'worker', 'group-b'],
    ]) {
      await setDoc(doc(db, 'users', id), { role, groupId, isActive:true, municipalityCoordinatorId:'coordinator' });
    }
    await setDoc(doc(db, 'users', 'coordinator'), {role:'municipality_coordinator', isActive:true});
    await setDoc(doc(db, 'users', 'coordinator-b'), {role:'municipality_coordinator', isActive:true});
    await setDoc(doc(db, 'users', 'inactive-head'), {role:'group_supervisor', groupId:'group-a', isActive:false});
    await setDoc(doc(db, 'operations', 'trip-a'), {
      _entity:'trip', groupId:'group-a', municipalityCoordinatorId:'coordinator', supervisorId:'head-a',
    });
    await setDoc(doc(db, 'messages', 'msg-a'), {
      messageId:'msg-a',senderId:'head-a',targetGroupId:'group-a',
      content:'Field report',type:'info',timestamp:Timestamp.now(),isRead:false,
    });
  });
});
const storage = (uid) => env.authenticatedContext(uid).storage(bucket);
const file = 'message_attachments/msg-a/photo-1.jpg';
const jpeg = new Uint8Array([0xff,0xd8,0xff,0xd9]);

test('operation photos: active owner uploads and own group/coordinator reads; other scopes cannot read or overwrite', async () => {
  const path = 'photos/head-a/trip-a/attachment.jpg';
  await assertSucceeds(uploadBytes(ref(storage('head-a'), path), jpeg, {contentType:'image/jpeg'}));
  for (const uid of ['head-a','worker-a','coordinator']) {
    await assertSucceeds(getBytes(ref(storage(uid), path)));
  }
  for (const uid of ['worker-b','coordinator-b','inactive-head']) {
    await assertFails(getBytes(ref(storage(uid), path)));
    await assertFails(uploadBytes(ref(storage(uid), path), jpeg, {contentType:'image/jpeg'}));
    await assertFails(deleteObject(ref(storage(uid), path)));
  }
  await assertFails(uploadBytes(ref(storage('worker-a'), 'photos/head-a/absent/new.jpg'), jpeg, {contentType:'image/jpeg'}));
  await assertSucceeds(deleteObject(ref(storage('head-a'), path)));
});

test('photo creation rejects inactive/anonymous owners and invalid size or type', async () => {
  await assertFails(uploadBytes(ref(storage('inactive-head'), 'photos/inactive-head/trip-a/new.jpg'), jpeg, {contentType:'image/jpeg'}));
  await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(bucket), 'photos/head-a/trip-a/new.jpg'), jpeg, {contentType:'image/jpeg'}));
  const own = ref(storage('head-a'), 'photos/head-a/trip-a/new.jpg');
  await assertFails(uploadBytes(own, jpeg, {contentType:'text/plain'}));
  await assertFails(uploadBytes(own, new Uint8Array(2 * 1024 * 1024 + 1), {contentType:'image/jpeg'}));
});

test('audio attachments retain owner upload and scoped reads', async () => {
  const path = 'audio/head-a/trip-a/emergency.m4a';
  await assertSucceeds(uploadBytes(ref(storage('head-a'), path), jpeg, {contentType:'audio/mp4'}));
  await assertSucceeds(getBytes(ref(storage('worker-a'), path)));
  await assertFails(getBytes(ref(storage('worker-b'), path)));
  await assertFails(uploadBytes(ref(storage('worker-a'), path), jpeg, {contentType:'audio/mp4'}));
  await assertFails(uploadBytes(ref(storage('head-a'), path), jpeg, {contentType:'image/jpeg'}));
});

test('sender uploads a JPEG and own group can read it', async () => {
  await assertSucceeds(uploadBytes(ref(storage('head-a'),file),jpeg,{contentType:'image/jpeg'}));
  await assertSucceeds(getBytes(ref(storage('worker-a'),file)));
  await assertSucceeds(getBytes(ref(storage('head-a'),file)));
  await assertFails(getBytes(ref(storage('worker-b'),file)));
});

test('non-sender cannot upload to an existing message', async () => {
  await assertFails(uploadBytes(ref(storage('worker-a'),file),jpeg,{contentType:'image/jpeg'}));
});

test('unrelated MIME and oversized image are denied', async () => {
  await assertFails(uploadBytes(ref(storage('head-a'),file),jpeg,{contentType:'text/plain'}));
  await assertFails(uploadBytes(ref(storage('head-a'),file),
    new Uint8Array(500 * 1024 + 1),{contentType:'image/jpeg'}));
});

test('attachment must belong to an existing message', async () => {
  await assertFails(uploadBytes(ref(storage('head-a'),
    'message_attachments/absent/photo-1.jpg'),jpeg,{contentType:'image/jpeg'}));
});
