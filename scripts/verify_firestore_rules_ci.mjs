// Exercises the local Firestore rules emulator, never production Firebase.
const base = 'http://127.0.0.1:8080/v1/projects/demo-cleanops/databases/(default)/documents';
async function assertRejected(method, resource) {
  const response = await fetch(base + resource, {
    method,
    headers: {'content-type': 'application/json'},
    ...(method === 'PATCH' ? {body: JSON.stringify({fields: {name: {stringValue: 'forbidden'}}})} : {}),
  });
  if (![401, 403].includes(response.status)) {
    throw new Error('Unauthenticated ' + method + ' ' + resource
        + ' unexpectedly returned ' + response.status + ': ' + (await response.text()).slice(0, 300));
  }
}
await assertRejected('GET', '/users/unknown-user');
await assertRejected('GET', '/operations/unknown-operation');
await assertRejected('PATCH', '/operations/unknown-operation');
console.log('Firestore emulator: anonymous protected reads and writes are rejected.');
