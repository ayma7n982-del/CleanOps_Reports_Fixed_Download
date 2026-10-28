import fs from 'node:fs';
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
const actorIds = [];

const ids = {
  supervisorA: `${prefix}_head_a`,
  supervisorB: `${prefix}_head_b`,
  workerA: `${prefix}_worker_a`,
  workerB: `${prefix}_worker_b`,
  deleteWorker: `${prefix}_worker_delete`,
  coordinator: `${prefix}_l2`,
  jsc: `${prefix}_l3`,
  manager: `${prefix}_l4`,
  groupA: `${prefix}_group_a`,
  groupB: `${prefix}_group_b`,
  tripA: `${prefix}_trip_a`,
  tripB: `${prefix}_trip_b`,
  ownCreate: `${prefix}_trip_created_by_a`,
  otherCreate: `${prefix}_trip_cross_create`,
  sosOwn: `${prefix}_sos_a`,
  sosOther: `${prefix}_sos_cross`,
  dumpsite: `${prefix}_dumpsite`,
  workerDumpsite: `${prefix}_worker_dumpsite`,
  cart: `${prefix}_cart`,
  redirectDenied: `${prefix}_redirect_denied`,
  redirectAllowed: `${prefix}_redirect_allowed`,
  deleteRequest: `${prefix}_delete_request`,
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
  actorIds.push(uid);
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
async function commit(token, writes) {
  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents:commit`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({writes}),
    },
  );
  const text = await response.text();
  return {status: response.status, ok: response.ok, text};
}
function updateWrite(path, data, fieldPaths) {
  return {
    update: {
      name: `${firestoreBase}/${path}`,
      fields: fields(data).fields,
    },
    updateMask: {fieldPaths},
  };
}
function createWrite(path, data) {
  return {
    update: {
      name: `${firestoreBase}/${path}`,
      fields: fields(data).fields,
    },
    currentDocument: {exists: false},
  };
}
function expectAllowed(label, result) {
  if (!result.ok) throw new Error(`${label}: expected allowed, got HTTP ${result.status}: ${result.text.slice(0, 700)}`);
  console.log(`PASS allowed: ${label}`);
}
function expectDenied(label, result) {
  if (![400, 401, 403].includes(result.status)) {
    throw new Error(`${label}: expected denial, got HTTP ${result.status}: ${result.text.slice(0, 700)}`);
  }
  console.log(`PASS denied: ${label}`);
}

const aiRef = adminDb.collection('ai_state').doc('command_center');
const aiBeforeSnap = await aiRef.get();
const aiBefore = aiBeforeSnap.exists ? aiBeforeSnap.data() : null;

try {
  await createTestUser(ids.coordinator, 'municipality_coordinator');
  await createTestUser(ids.jsc, 'jsc_coordinator');
  await createTestUser(ids.manager, 'donor_manager');
  await createTestUser(ids.supervisorA, 'group_supervisor', ids.groupA);
  await createTestUser(ids.supervisorB, 'group_supervisor', ids.groupB);
  await createTestUser(ids.workerA, 'worker', ids.groupA);
  await createTestUser(ids.workerB, 'worker', ids.groupB);
  await createTestUser(ids.deleteWorker, 'worker', ids.groupA);

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
  await adminSet('equipment', ids.cart, {
    id: ids.cart, name: 'Smoke Cart', type: 'cart', category: 'cart',
    municipalityCoordinatorId: ids.coordinator,
    groupId: ids.groupA, isDeleted: false,
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

  expectAllowed('municipality coordinator transfers managed worker to another owned group',
    await rest('PATCH', `users/${ids.workerA}`, tokens.coordinator, {
      groupId: ids.groupB,
      groupName: 'Smoke Group B',
      updatedBy: ids.coordinator,
      updatedAt: new Date().toISOString(),
    }, '?updateMask.fieldPaths=groupId&updateMask.fieldPaths=groupName&updateMask.fieldPaths=updatedBy&updateMask.fieldPaths=updatedAt'));

  expectDenied('group supervisor cannot transfer worker profile',
    await rest('PATCH', `users/${ids.workerB}`, tokens.supervisorA, {
      groupId: ids.groupA,
    }, '?updateMask.fieldPaths=groupId'));

  const dumpsite = {
    nameAr: 'مكب اختبار مؤقت',
    nameEn: 'Temporary Smoke Dumpsite',
    capacity: 100,
    fillPercentage: 25,
    isActive: true,
    createdBy: ids.coordinator,
    createdAt: new Date().toISOString(),
  };
  rememberDoc('dumpsites', ids.dumpsite);
  expectAllowed('municipality coordinator creates a valid dumpsite',
    await rest('PATCH', `dumpsites/${ids.dumpsite}`, tokens.coordinator, dumpsite));
  rememberDoc('dumpsites', ids.workerDumpsite);
  expectDenied('worker cannot create dumpsite',
    await rest('PATCH', `dumpsites/${ids.workerDumpsite}`, tokens.workerA, dumpsite));

  const sos = {
    id: ids.sosOwn, _entity: 'emergency',
    reportedBy: ids.supervisorA, userId: ids.supervisorA,
    groupId: ids.groupA, municipalityCoordinatorId: ids.coordinator,
    latitude: 31.9, longitude: 35.2, street: 'Smoke Test Street',
    status: 'urgent', statusLevel: 'critical', acknowledged: false,
    createdAt: new Date().toISOString(), isDeleted: false,
  };
  rememberDoc('operations', ids.sosOwn);
  expectAllowed('supervisor creates SOS for own group',
    await rest('PATCH', `operations/${ids.sosOwn}`, tokens.supervisorA, sos));
  rememberDoc('operations', ids.sosOther);
  expectDenied('supervisor cannot create SOS for another group',
    await rest('PATCH', `operations/${ids.sosOther}`, tokens.supervisorA, {
      ...sos, id: ids.sosOther, groupId: ids.groupB,
    }));

  expectDenied('supervisor cannot redirect municipality cart',
    await callable('redirectCartAssignment', tokens.supervisorA, {
      requestId: ids.redirectDenied, cartId: ids.cart,
      cartCollection: 'equipment', fromGroupId: ids.groupA, toGroupId: ids.groupB,
    }));
  rememberDoc('operations', ids.redirectAllowed);
  expectAllowed('municipality coordinator redirects managed cart between owned groups',
    await callable('redirectCartAssignment', tokens.coordinator, {
      requestId: ids.redirectAllowed, cartId: ids.cart,
      cartCollection: 'equipment', fromGroupId: ids.groupA, toGroupId: ids.groupB,
    }));
  const cartAfter = await adminDb.collection('equipment').doc(ids.cart).get();
  if (cartAfter.data()?.groupId !== ids.groupB) {
    throw new Error('Cart redirect callable returned success but equipment assignment did not change.');
  }
  console.log('PASS verified: cart assignment changed on production Firestore.');

  expectAllowed('municipality coordinator permanently deletes managed temporary worker',
    await callable('deleteManagedUser', tokens.coordinator, {userId: ids.deleteWorker}));
  const deletedProfile = await adminDb.collection('users').doc(ids.deleteWorker).get();
  if (deletedProfile.exists) throw new Error('deleteManagedUser left the temporary Firestore profile behind.');
  let deletedAuthStillExists = true;
  try { await auth.getUser(ids.deleteWorker); } catch (error) {
    if (error?.code === 'auth/user-not-found') deletedAuthStillExists = false;
    else throw error;
  }
  if (deletedAuthStillExists) throw new Error('deleteManagedUser left the temporary Authentication account behind.');
  console.log('PASS verified: managed worker removed from Auth and Firestore.');

  console.log('PRODUCTION FIREBASE SECURITY AND OPERATIONS SMOKE TEST PASSED.');
} finally {
  try {
    const audits = await adminDb.collection('audit').where('actorId', 'in', actorIds.slice(0, 10)).get();
    for (const doc of audits.docs) {
      try { await doc.ref.delete(); } catch (error) { console.error(`Cleanup audit failed ${doc.ref.path}: ${error}`); }
    }
  } catch (error) {
    console.error(`Cleanup audit query failed: ${error}`);
  }

  for (const ref of [...new Map(createdDocs.map(ref => [ref.path, ref])).values()].reverse()) {
    try { await ref.delete(); } catch (error) { console.error(`Cleanup document failed ${ref.path}: ${error}`); }
  }
  for (const uid of [...createdUids].reverse()) {
    try { await auth.deleteUser(uid); } catch (error) {
      if (error?.code !== 'auth/user-not-found') console.error(`Cleanup auth user failed ${uid}: ${error}`);
    }
  }

  await new Promise(resolve => setTimeout(resolve, 5000));
  try {
    if (aiBeforeSnap.exists) await aiRef.set(aiBefore, {merge: false});
    else await aiRef.delete();
  } catch (error) {
    console.error(`Cleanup ai_state restore failed: ${error}`);
  }
  await deleteApp(app);
}
