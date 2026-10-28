// Firestore Security Rules tests run only against the local emulator.
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, getDoc, setDoc} from 'firebase/firestore';

const projectId = 'demo-cleanops';
const env = await initializeTestEnvironment({projectId});

try {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', 'worker-a'), {
      role: 'worker', groupId: 'group-a', isActive: true,
    });
    await setDoc(doc(db, 'users', 'supervisor-a'), {
      role: 'group_supervisor', groupId: 'group-a', isActive: true,
    });
    await setDoc(doc(db, 'users', 'worker-inactive'), {
      role: 'worker', groupId: 'group-a', isActive: false,
    });
    await setDoc(doc(db, 'users', 'municipality-a'), {
      role: 'municipality_coordinator', scope: 'Municipality A', isActive: true,
    });
    await setDoc(doc(db, 'users', 'jsc-a'), {
      role: 'jsc_coordinator', scope: 'Council A', isActive: true,
    });
    await setDoc(doc(db, 'users', 'manager-a'), {
      role: 'donor_manager', scope: 'all', isActive: true,
    });

    await setDoc(doc(db, 'operations', 'trip-a'), {
      _entity: 'trip', groupId: 'group-a', reportedBy: 'supervisor-a',
    });
    await setDoc(doc(db, 'operations', 'trip-b'), {
      _entity: 'trip', groupId: 'group-b', reportedBy: 'supervisor-b',
    });
    await setDoc(doc(db, 'operations', 'target-worker-a'), {
      _entity: 'notification', targetUserId: 'worker-a',
    });
  });

  const anonymous = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, 'operations', 'trip-a')));

  const worker = env.authenticatedContext('worker-a').firestore();
  await assertSucceeds(getDoc(doc(worker, 'operations', 'trip-a')));
  await assertSucceeds(getDoc(doc(worker, 'operations', 'target-worker-a')));
  await assertFails(getDoc(doc(worker, 'operations', 'trip-b')));

  const supervisor = env.authenticatedContext('supervisor-a').firestore();
  await assertSucceeds(getDoc(doc(supervisor, 'operations', 'trip-a')));
  await assertFails(getDoc(doc(supervisor, 'operations', 'trip-b')));

  const inactive = env.authenticatedContext('worker-inactive').firestore();
  await assertFails(getDoc(doc(inactive, 'operations', 'trip-a')));

  for (const uid of ['municipality-a', 'jsc-a', 'manager-a']) {
    const db = env.authenticatedContext(uid).firestore();
    await assertSucceeds(getDoc(doc(db, 'operations', 'trip-a')));
    await assertSucceeds(getDoc(doc(db, 'operations', 'trip-b')));
  }

  console.log('Firestore emulator: operations reads are management-only or scoped to the active workforce user/group.');
} finally {
  await env.cleanup();
}
