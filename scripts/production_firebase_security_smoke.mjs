import fs from 'node:fs';
import crypto from 'node:crypto';
import {initializeApp, cert, deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore} from 'firebase-admin/firestore';

const projectId = process.env.FIREBASE_PROJECT_ID || 'nrc-aid';
const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is missing.');
const serviceAccount = JSON.parse(raw);
if (serviceAccount.project_id && serviceAccount.project_id !== projectId) {
  throw new Error(`Service account belongs to ${serviceAccount.project_id}, expected ${projectId}.`);
}

const googleServices = JSON.parse(fs.readFileSync('android/app/google-services.json', 'utf8'));
const apiKey = googleServices.client?.[0]?.api_key?.[0]?.current_key;
if (!apiKey) throw new Error('Firebase Web API key not found in google-services.json.');

const suffix = (process.env.GITHUB_RUN_ID || Date.now().toString()).replace(/[^0-9A-Za-z_-]/g, '');
const prefix = `__cleanops_smoke_${suffix}`;
const app = initializeApp({credential: cert(serviceAccount), projectId});
const auth = getAuth(app);
const adminDb = getFirestore(app);
const createdUids = [];
const createdDocs = [];

const ids = {
  supervisorA: `${prefix}_head_a`,
  supervisorB: `${prefix}_head_b`,
  workerA: `${prefix}_worker_a`,
  workerB: `${prefix}_worker_b`,
  coordinator: `${prefix}_l2`,
  jsc: `${prefix}_l3`,
  manager: `${prefix}_l4`,
  groupA: `${prefix}_group_a`,
  groupB: `${prefix}_group_b`,
  tripA: `${prefix}_trip_a`,
  tripB: `${prefix}_trip_b`,
  ownCreate: `${prefix}_trip_created_by_a`,
  otherCreate: `${prefix}_trip_cross_create`,
};

function rememberDoc(collection, id) {
  createdDocs.push(adminDb.collection(collection).doc(id));
}
async function adminSet(collection, id, data) {
  const ref = adminDb.collection(collection).doc(id);
  createdDocs.push(ref);
  await ref.set(data);
}
async function createTestUser(uid, role, groupId = null) {
  await auth.createUser({uid, disabled: false});
  createdUids.push(uid);
  const data = {
    id: uid,
    username: uid.slice(-28),
    name: `CleanOps Smoke ${role}`,
    role,
    scope: role === 'municipality_coordinator' ? 'Smoke Municipality'
      : role === 'jsc_coordinator' ? 'Smoke Council'
      : role === 'donor_manager' ? 'all' : 'assigned_only',
    isActive: true,
    status: 'active',
    createdAt: new Date().toISOString(),
  };
  if (groupId) data.groupId = groupId;
  if (role === 'group_supervisor' || role === 'worker') {
    data.municipalityCoordinatorId = ids.coordinator;
    data.municipalityName = 'Smoke Municipality';
  }
  await adminSet('users', uid, data);
}

async function idToken(uid) {
  const customToken = await auth.createCustomToken(uid);
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({token: customToken, returnSecureToken: true}),
    },
  );
  const body = await response.text();
  if (!response.ok) throw new Error(`Custom-token sign-in failed for ${uid} (${response.status}): ${body}`);
  const parsed = JSON.parse(body);
  if (!parsed.idToken) throw new Error(`No idToken returned for ${uid}.`);
  return parsed.idToken;
}

const firestoreBase = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`;
function fields(data) {
  const out = {};
  for (const [key, value] of Object.entries(data)) {
    if (value === null || value === undefined) continue;
    if (typeof value === 'string') out[key] = {stringValue: value};
    else if (typeof value === 'boolean') out[key] = {booleanValue: value};
    else if (Number.isInteger(value)) out[key] = {integerValue: String(value)};
    else if (typeof value === 'number') out[key] = {doubleValue: value};
    else throw new Error(`Unsupported smoke-test field ${key}: ${typeof value}`);
  }
  return {fields: out};
}
async function rest(method, path, token, data, query = '') {
  const response = await fetch(`${firestoreBase}/${path}${query}`, {
    method,
    headers: {
      ...(token ? {authorization: `Bearer ${token}`} : {}),
      ...(data ? {'content-type': 'application/json'} : {}),
    },
    ...(data ? {body: JSON.stringify(fields(data))} : {}),
  });
  const text = await response.text();
  return {status: response.status, ok: response.ok, text};
}
function expectAllowed(label, result) {
  if (!result.ok) throw new Error(`${label}: expected allowed, got HTTP ${result.status}: ${result.text.slice(0, 500)}`);
  console.log(`PASS allowed: ${label}`);
}
function expectDenied(label, result) {
  if (![401, 403].includes(result.status)) {
    throw new Error(`${label}: expected 401/403, got HTTP ${result.status}: ${result.text.slice(0, 500)}`);
  }
  console.log(`PASS denied: ${label}`);
}

try {
  await createTestUser(ids.coordinator, 'municipality_coordinator');
  await createTestUser(ids.jsc, 'jsc_coordinator');
  await createTestUser(ids.manager, 'donor_manager');
  await createTestUser(ids.supervisorA, 'group_supervisor', ids.groupA);
  await createTestUser(ids.supervisorB, 'group_supervisor', ids.groupB);
  await createTestUser(ids.workerA, 'worker', ids.groupA);
  await createTestUser(ids.workerB, 'worker', ids.groupB);

  await adminSet('operations', ids.groupA, {
    id: ids.groupA, _entity: 'group', name: 'Smoke Group A',
    municipalityCoordinatorId: ids.coordinator,
  });
  await adminSet('operations', ids.groupB, {
    id: ids.groupB, _entity: 'group', name: 'Smoke Group B',
    municipalityCoordinatorId: ids.coordinator,
  });
  await adminSet('operations', ids.tripA, {
    id: ids.tripA, _entity: 'trip', groupId: ids.groupA,
    supervisorId: ids.supervisorA, status: 'in_progress',
    startedAt: new Date(Date.now() - 10 * 60_000).toISOString(),
    deadlineAt: new Date(Date.now() + 50 * 60_000).toISOString(),
    createdAt: new Date().toISOString(), isDeleted: false,
  });
  await adminSet('operations', ids.tripB, {
    id: ids.tripB, _entity: 'trip', groupId: ids.groupB,
    supervisorId: ids.supervisorB, status: 'in_progress',
    startedAt: new Date(Date.now() - 10 * 60_000).toISOString(),
    deadlineAt: new Date(Date.now() + 50 * 60_000).toISOString(),
    createdAt: new Date().toISOString(), isDeleted: false,
  });

  const tokens = {};
  for (const [name, uid] of Object.entries({
    supervisorA: ids.supervisorA, supervisorB: ids.supervisorB,
    workerA: ids.workerA, workerB: ids.workerB,
    coordinator: ids.coordinator, jsc: ids.jsc, manager: ids.manager,
  })) tokens[name] = await idToken(uid);

  expectDenied('anonymous cannot read operations',
    await rest('GET', `operations/${ids.tripA}`, null));

  expectAllowed('worker A reads own-group trip',
    await rest('GET', `operations/${ids.tripA}`, tokens.workerA));
  expectDenied('worker A cannot read group B trip',
    await rest('GET', `operations/${ids.tripB}`, tokens.workerA));
  expectAllowed('supervisor A reads own-group trip',
    await rest('GET', `operations/${ids.tripA}`, tokens.supervisorA));
  expectDenied('supervisor A cannot read group B trip',
    await rest('GET', `operations/${ids.tripB}`, tokens.supervisorA));

  for (const role of ['coordinator', 'jsc', 'manager']) {
    expectAllowed(`${role} retains management read access`,
      await rest('GET', `operations/${ids.tripB}`, tokens[role]));
  }

  const ownCreate = {
    id: ids.ownCreate, _entity: 'trip', groupId: ids.groupA,
    supervisorId: ids.supervisorA, status: 'in_progress',
    startedAt: new Date().toISOString(),
    deadlineAt: new Date(Date.now() + 60 * 60_000).toISOString(),
    createdAt: new Date().toISOString(), isDeleted: false,
  };
  rememberDoc('operations', ids.ownCreate);
  expectAllowed('supervisor A creates own-group trip',
    await rest('PATCH', `operations/${ids.ownCreate}`, tokens.supervisorA, ownCreate));

  const otherCreate = {...ownCreate, id: ids.otherCreate, groupId: ids.groupB};
  rememberDoc('operations', ids.otherCreate);
  expectDenied('supervisor A cannot create trip for group B',
    await rest('PATCH', `operations/${ids.otherCreate}`, tokens.supervisorA, otherCreate));

  expectDenied('worker cannot create trip',
    await rest('PATCH', `operations/${prefix}_worker_trip`, tokens.workerA, {
      ...ownCreate, id: `${prefix}_worker_trip`, supervisorId: ids.workerA,
    }));

  expectAllowed('supervisor A completes own-group trip',
    await rest('PATCH', `operations/${ids.tripA}`, tokens.supervisorA, {
      status: 'completed',
      completedBy: ids.supervisorA,
      completedAt: new Date().toISOString(),
    }, '?updateMask.fieldPaths=status&updateMask.fieldPaths=completedBy&updateMask.fieldPaths=completedAt'));

  expectDenied('supervisor A cannot complete group B trip',
    await rest('PATCH', `operations/${ids.tripB}`, tokens.supervisorA, {
      status: 'completed',
      completedBy: ids.supervisorA,
      completedAt: new Date().toISOString(),
    }, '?updateMask.fieldPaths=status&updateMask.fieldPaths=completedBy&updateMask.fieldPaths=completedAt'));

  expectDenied('supervisor cannot arbitrarily edit own trip destination',
    await rest('PATCH', `operations/${ids.tripA}`, tokens.supervisorA, {
      landfill: 'unauthorized-change',
    }, '?updateMask.fieldPaths=landfill'));

  console.log('PRODUCTION FIREBASE SECURITY SMOKE TEST PASSED.');
} finally {
  for (const ref of [...new Map(createdDocs.map(ref => [ref.path, ref])).values()].reverse()) {
    try { await ref.delete(); } catch (error) { console.error(`Cleanup document failed ${ref.path}: ${error}`); }
  }
  for (const uid of [...createdUids].reverse()) {
    try { await auth.deleteUser(uid); } catch (error) { console.error(`Cleanup auth user failed ${uid}: ${error}`); }
  }
  await deleteApp(app);
}
