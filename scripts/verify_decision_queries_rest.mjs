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
const root = 'projects/' + project + '/databases/(default)/documents';
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

const probe = '__cleanops_query_verification_no_write__';
const cases = [
  ['scoped-operations', root, 'operations', [['_entity', 'trip'], ['municipalityCoordinatorId', probe]]],
  ['own-group-directives', root, 'strategic_decisions', [['groupId', probe]]],
  ['global-broadcast', root, 'strategic_decisions', [['scopeKey', 'global'], ['kind', 'broadcast']]],
  ['municipality-broadcast', root, 'strategic_decisions', [['scopeKey', 'municipality:' + probe], ['kind', 'broadcast']]],
  ['adjacent-coverage', root, 'strategic_decisions', [['additionalGroupId', probe], ['kind', 'temporary_coverage']]],
  ['scoped-container-history', root + '/containers/' + probe, 'status_events', [['municipalityId', probe]]],
];
for (const [label, parent, collectionId, filters] of cases) {
  const fieldFilters = filters.map(([fieldPath, stringValue]) => ({
    fieldFilter: {field: {fieldPath}, op: 'EQUAL', value: {stringValue}},
  }));
  await request(parent + ':runQuery', 'POST', {structuredQuery: {
    select: {fields: [{fieldPath: '__name__'}]}, from: [{collectionId}],
    where: fieldFilters.length === 1 ? fieldFilters[0] :
      {compositeFilter: {op: 'AND', filters: fieldFilters}}, limit: 1,
  }});
  // No document fields or identifiers are printed, and no data is written.
  console.log('PASS default-index production query: ' + label);
}
console.log('Verified all six decision query shapes without creating indexes or changing data.');
