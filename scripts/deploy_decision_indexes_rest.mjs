import fs from 'node:fs';
import crypto from 'node:crypto';

const project = process.env.FIREBASE_PROJECT_ID || 'nrc-aid';
const account = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || '{}');
if (!account.client_email || !account.private_key) throw new Error('Missing service account.');
if (account.project_id && account.project_id !== project) throw new Error('Wrong Firebase project.');
const now = Math.floor(Date.now() / 1000);
const encode = value => Buffer.from(value).toString('base64url');
const header = encode(JSON.stringify({alg: 'RS256', typ: 'JWT'}));
const claims = encode(JSON.stringify({iss: account.client_email,
  scope: 'https://www.googleapis.com/auth/datastore',
  aud: account.token_uri || 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600}));
const unsigned = header + '.' + claims;
const jwt = unsigned + '.' + crypto.sign('RSA-SHA256', Buffer.from(unsigned), account.private_key).toString('base64url');
const auth = await fetch(account.token_uri || 'https://oauth2.googleapis.com/token', {
  method: 'POST', headers: {'content-type': 'application/x-www-form-urlencoded'},
  body: new URLSearchParams({grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: jwt}),
});
if (!auth.ok) throw new Error('OAuth failed: ' + auth.status);
const token = (await auth.json()).access_token;
if (!token) throw new Error('No OAuth token.');
const api = 'https://firestore.googleapis.com/v1/';
const root = 'projects/' + project + '/databases/(default)/collectionGroups/';
const headers = {authorization: 'Bearer ' + token, 'content-type': 'application/json'};
async function request(path, method = 'GET', body) {
  const response = await fetch(api + path, {method, headers,
    ...(body ? {body: JSON.stringify(body)} : {})});
  const raw = await response.text();
  if (!response.ok) {
    // These are administrative API errors, never token/credential responses.
    throw new Error(method + ' ' + path + ' failed (' + response.status + '): ' + raw);
  }
  return raw ? JSON.parse(raw) : {};
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function complete(operation) {
  if (!operation.name) throw new Error('No operation name.');
  for (let attempt = 0; attempt < 120; attempt++) {
    const state = attempt === 0 ? operation : await request(operation.name);
    if (state.error) throw new Error('Index operation failed: ' + JSON.stringify(state.error));
    if (state.done) return;
    await sleep(5000);
  }
  throw new Error('Index build has not completed after 10 minutes.');
}
function clean(index) {
  return {queryScope: index.queryScope, fields: index.fields
    .filter(f => f.fieldPath !== '__name__')
    .map(f => ({fieldPath: f.fieldPath,
      ...(f.order ? {order: f.order} : {}),
      ...(f.arrayConfig ? {arrayConfig: f.arrayConfig} : {})}))};
}
const signature = index => JSON.stringify(clean(index));
const config = JSON.parse(fs.readFileSync('firebase/firestore.indexes.json', 'utf8'));
const requested = config.indexes.filter(i => i.collectionGroup === 'strategic_decisions');
let existing = [], pageToken;
do {
  const result = await request(root + 'strategic_decisions/indexes' +
    (pageToken ? '?pageToken=' + encodeURIComponent(pageToken) : ''));
  existing.push(...(result.indexes || []));
  pageToken = result.nextPageToken;
} while (pageToken);
const operations = [];
for (const index of requested) {
  const match = existing.find(i => signature(i) === signature(index));
  if (match?.state === 'NEEDS_REPAIR') throw new Error('Existing index needs repair: ' + match.name);
  if (!match) {
    operations.push(await request(root + 'strategic_decisions/indexes', 'POST', clean(index)));
    console.log('Requested decision index: ' + index.fields.map(f => f.fieldPath).join(', '));
  }
}
const override = config.fieldOverrides.find(x =>
  x.collectionGroup === 'status_events' && x.fieldPath === 'municipalityId');
if (!override) throw new Error('Missing scoped status-event index configuration.');
const fieldName = root + 'status_events/fields/municipalityId';
const field = await request(fieldName);
const inherited = (field.indexConfig?.indexes || []).map(clean);
const wanted = override.indexes.map(i => ({queryScope: i.queryScope,
  fields: [{fieldPath: override.fieldPath,
    ...(i.order ? {order: i.order} : {}), ...(i.arrayConfig ? {arrayConfig: i.arrayConfig} : {})}]}));
const merged = new Map(inherited.map(i => [signature(i), i]));
for (const i of wanted) merged.set(signature(i), i);
if (wanted.some(i => !inherited.some(old => signature(old) === signature(i)))) {
  operations.push(await request(fieldName + '?updateMask=indexConfig', 'PATCH',
    {name: fieldName, indexConfig: {indexes: [...merged.values()]}}));
  console.log('Requested scoped status-event collection-group index.');
}
// Wait for acknowledged administrative operations, rather than treating
// "creation requested" as proof that the queries are usable.
for (const operation of operations) await complete(operation);
for (let attempt = 0; attempt < 120; attempt++) {
  const list = await request(root + 'strategic_decisions/indexes');
  const currentField = await request(fieldName);
  const ready = requested.every(i => (list.indexes || []).some(x =>
    signature(x) === signature(i) && x.state === 'READY'));
  const fieldReady = wanted.every(i => (currentField.indexConfig?.indexes || []).some(x =>
    signature(x) === signature(i) && x.state === 'READY'));
  if (ready && fieldReady) {
    console.log('Verified READY: ' + requested.length +
      ' decision indexes and scoped status-event indexes in ' + project + '.');
    process.exit(0);
  }
  await sleep(5000);
}
throw new Error('Indexes were requested, but READY state has not been verified.');
