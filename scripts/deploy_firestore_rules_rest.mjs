import fs from 'node:fs';
import crypto from 'node:crypto';

const projectId = process.env.FIREBASE_PROJECT_ID || 'nrc-aid';
const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is missing.');

let serviceAccount;
try {
  serviceAccount = JSON.parse(raw);
} catch (error) {
  throw new Error('FIREBASE_SERVICE_ACCOUNT is not valid JSON.');
}
if (!serviceAccount.client_email || !serviceAccount.private_key) {
  throw new Error('Service account JSON is missing client_email or private_key.');
}
if (serviceAccount.project_id && serviceAccount.project_id !== projectId) {
  throw new Error(
    `Service account belongs to ${serviceAccount.project_id}, expected ${projectId}.`,
  );
}

const base64url = (value) => Buffer.from(value)
  .toString('base64')
  .replace(/=/g, '')
  .replace(/\+/g, '-')
  .replace(/\//g, '_');

const now = Math.floor(Date.now() / 1000);
const header = base64url(JSON.stringify({alg: 'RS256', typ: 'JWT'}));
const claims = base64url(JSON.stringify({
  iss: serviceAccount.client_email,
  scope: 'https://www.googleapis.com/auth/firebase',
  aud: serviceAccount.token_uri || 'https://oauth2.googleapis.com/token',
  iat: now,
  exp: now + 3600,
}));
const unsigned = `${header}.${claims}`;
const signature = crypto.sign('RSA-SHA256', Buffer.from(unsigned), serviceAccount.private_key);
const assertion = `${unsigned}.${base64url(signature)}`;

const tokenResponse = await fetch(serviceAccount.token_uri || 'https://oauth2.googleapis.com/token', {
  method: 'POST',
  headers: {'content-type': 'application/x-www-form-urlencoded'},
  body: new URLSearchParams({
    grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
    assertion,
  }),
});
if (!tokenResponse.ok) {
  throw new Error(`OAuth token request failed (${tokenResponse.status}): ${await tokenResponse.text()}`);
}
const {access_token: accessToken} = await tokenResponse.json();
if (!accessToken) throw new Error('OAuth token response did not include access_token.');

const api = 'https://firebaserules.googleapis.com/v1';
const authHeaders = {
  authorization: `Bearer ${accessToken}`,
  'content-type': 'application/json',
};

const source = fs.readFileSync('firebase/firestore.rules', 'utf8');
const rulesetResponse = await fetch(`${api}/projects/${projectId}/rulesets`, {
  method: 'POST',
  headers: authHeaders,
  body: JSON.stringify({
    source: {files: [{name: 'firestore.rules', content: source}]},
  }),
});
const rulesetBody = await rulesetResponse.text();
if (!rulesetResponse.ok) {
  throw new Error(`Ruleset creation failed (${rulesetResponse.status}): ${rulesetBody}`);
}
const ruleset = JSON.parse(rulesetBody);
if (!ruleset.name) throw new Error('Ruleset creation succeeded without a ruleset name.');

const releaseName = `projects/${projectId}/releases/cloud.firestore`;
const releaseUrl = `${api}/${releaseName}`;
const patchResponse = await fetch(releaseUrl, {
  method: 'PATCH',
  headers: authHeaders,
  body: JSON.stringify({
    release: {name: releaseName, rulesetName: ruleset.name},
    updateMask: 'rulesetName',
  }),
});

let release;
if (patchResponse.status === 404) {
  const createResponse = await fetch(`${api}/projects/${projectId}/releases`, {
    method: 'POST',
    headers: authHeaders,
    body: JSON.stringify({name: releaseName, rulesetName: ruleset.name}),
  });
  const createBody = await createResponse.text();
  if (!createResponse.ok) {
    throw new Error(`Release creation failed (${createResponse.status}): ${createBody}`);
  }
  release = JSON.parse(createBody);
} else {
  const patchBody = await patchResponse.text();
  if (!patchResponse.ok) {
    throw new Error(`Release update failed (${patchResponse.status}): ${patchBody}`);
  }
  release = JSON.parse(patchBody);
}

const verifyResponse = await fetch(releaseUrl, {headers: {authorization: `Bearer ${accessToken}`}});
const verifyBody = await verifyResponse.text();
if (!verifyResponse.ok) {
  throw new Error(`Release verification failed (${verifyResponse.status}): ${verifyBody}`);
}
const verified = JSON.parse(verifyBody);
if (verified.rulesetName !== ruleset.name) {
  throw new Error(`Release verification mismatch: expected ${ruleset.name}, got ${verified.rulesetName}`);
}

console.log(`Firestore rules deployed to ${projectId}: ${release.name}`);
console.log(`Ruleset: ${ruleset.name}`);
