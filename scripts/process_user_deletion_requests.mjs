import {initializeApp, cert, deleteApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore, FieldValue} from 'firebase-admin/firestore';

const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
if (!raw) throw new Error('FIREBASE_SERVICE_ACCOUNT is missing.');
const serviceAccount = JSON.parse(raw);
const projectId = process.env.FIREBASE_PROJECT_ID || serviceAccount.project_id;
if (!projectId) throw new Error('Firebase project ID is missing.');

const app = initializeApp({credential: cert(serviceAccount), projectId});
const auth = getAuth(app);
const db = getFirestore(app);

async function reject(ref, reason) {
  await ref.set({
    status: 'rejected',
    processedAt: FieldValue.serverTimestamp(),
    failureReason: reason,
  }, {merge: true});
}

let processed = 0;
let rejected = 0;

try {
  const snap = await db.collection('admin_requests')
    .where('status', '==', 'pending')
    .limit(100)
    .get();

  for (const requestDoc of snap.docs) {
    const request = requestDoc.data();
    if (request.type !== 'delete_user') continue;

    const actorId = String(request.requestedBy ?? '').trim();
    const targetId = String(request.targetUserId ?? '').trim();
    if (!actorId || !targetId || actorId === targetId) {
      await reject(requestDoc.ref, 'invalid_request');
      rejected++;
      continue;
    }

    const [actorSnap, targetSnap] = await Promise.all([
      db.collection('users').doc(actorId).get(),
      db.collection('users').doc(targetId).get(),
    ]);
    if (!actorSnap.exists || !targetSnap.exists) {
      // A previously completed/partial cleanup is idempotently finalized.
      let authExists = true;
      try { await auth.getUser(targetId); } catch (error) {
        if (error?.code === 'auth/user-not-found') authExists = false;
        else throw error;
      }
      if (!targetSnap.exists && !authExists) {
        await requestDoc.ref.set({
          status: 'completed',
          processedAt: FieldValue.serverTimestamp(),
          targetUserId: targetId,
          alreadyAbsent: true,
        }, {merge: true});
        processed++;
        continue;
      }
      await reject(requestDoc.ref, 'actor_or_target_profile_missing');
      rejected++;
      continue;
    }

    const actor = actorSnap.data() ?? {};
    const target = targetSnap.data() ?? {};
    const actorRole = String(actor.role ?? '');
    const targetRole = String(target.role ?? '');
    const targetIsWorkforce =
      targetRole === 'worker' || targetRole === 'group_supervisor';
    const allowed = actor.isActive !== false && (
      actorRole === 'donor_manager' ||
      (actorRole === 'municipality_coordinator' &&
        targetIsWorkforce &&
        String(target.municipalityCoordinatorId ?? '') === actorId)
    );
    const requestMatchesTarget =
      target.status === 'pending_deletion' &&
      target.isActive === false &&
      String(target.deletionRequestId ?? '') === requestDoc.id &&
      String(target.deletionRequestedBy ?? '') === actorId;

    if (!allowed || !requestMatchesTarget) {
      await reject(requestDoc.ref, allowed ? 'target_state_mismatch' : 'permission_denied');
      rejected++;
      continue;
    }

    let deletedAuth = false;
    try {
      await auth.deleteUser(targetId);
      deletedAuth = true;
    } catch (error) {
      if (error?.code !== 'auth/user-not-found') throw error;
    }

    await db.runTransaction(async tx => {
      const latestRequest = await tx.get(requestDoc.ref);
      const latestTarget = await tx.get(targetSnap.ref);
      if (!latestRequest.exists || latestRequest.data()?.status !== 'pending') return;
      if (latestTarget.exists) tx.delete(targetSnap.ref);
      tx.set(requestDoc.ref, {
        status: 'completed',
        processedAt: FieldValue.serverTimestamp(),
        deletedAuth,
        deletedProfile: latestTarget.exists,
      }, {merge: true});
      const auditRef = db.collection('audit').doc();
      tx.set(auditRef, {
        actorId,
        operation: 'DELETE_USER_GITHUB_WORKER',
        targetId,
        before: {role: targetRole, pendingDeletion: true},
        after: {deletedAuth, deletedProfile: latestTarget.exists},
        createdAt: new Date().toISOString(),
        timestamp: FieldValue.serverTimestamp(),
        immutable: true,
      });
    });
    processed++;
    console.log(`Deleted managed user ${targetId} for request ${requestDoc.id}.`);
  }

  console.log(`Deletion worker complete. processed=${processed}, rejected=${rejected}`);
} finally {
  await deleteApp(app);
}
