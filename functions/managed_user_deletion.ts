import { Auth } from 'firebase-admin/auth';
import { Firestore, FieldValue } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

const notFound = (error: unknown) => (error as { code?: string })?.code === 'auth/user-not-found';

/** Delete the account, not its historical operations. All cleanup is retryable. */
export async function deleteManagedAccount(db: Firestore, auth: Auth, actorId: string, uid: string) {
  if (!uid || uid === actorId) throw new HttpsError('failed-precondition', 'لا يمكن حذف الحساب الحالي أو معرّف فارغ.');
  const actor = (await db.collection('users').doc(actorId).get()).data();
  if (!actor || actor.isActive === false || actor.status === 'deleted') {
    throw new HttpsError('permission-denied', 'حساب المسؤول غير نشط.');
  }
  const profileRef = db.collection('users').doc(uid);
  const jobRef = db.collection('account_deletions').doc(uid);
  const profile = await profileRef.get();
  const prior = (await jobRef.get()).data();
  const target = profile.data() ?? prior?.target ?? null;
  const allowed = actor.role === 'donor_manager' || (actor.role === 'municipality_coordinator'
    && target && ['worker', 'group_supervisor'].includes(String(target.role))
    && target.municipalityCoordinatorId === actorId);
  if (!allowed) throw new HttpsError('permission-denied', 'لا تملك صلاحية حذف هذا المستخدم.');
  let authBefore;
  try { authBefore = await auth.getUser(uid); }
  catch (error) { if (!notFound(error)) throw error; }
  const metadata = target ?? { role: 'unknown', name: authBefore?.displayName ?? '' };
  await db.runTransaction(async tx => {
    const job = await tx.get(jobRef);
    if (!job.exists) tx.set(jobRef, {
      target: { name: metadata.name ?? '', role: metadata.role ?? '',
        municipalityCoordinatorId: metadata.municipalityCoordinatorId ?? '' },
      requestedBy: actorId, requestedAt: FieldValue.serverTimestamp(), status: 'pending',
    });
  });
  // Stop further use first; a failed cleanup can safely be retried.
  if (profile.exists) await profileRef.update({ isActive: false, status: 'pending_deletion', updatedAt: FieldValue.serverTimestamp() });
  if (authBefore) {
    try { await auth.updateUser(uid, { disabled: true }); await auth.revokeRefreshTokens(uid); }
    catch (error) { if (!notFound(error)) throw error; }
    try { await auth.deleteUser(uid); }
    catch (error) { if (!notFound(error)) throw error; }
  }
  // Keep inactive worker projections as tombstones so offline caches receive
  // a removal signal. Never change attendance, trips, or work reports.
  const linked = await db.collection('operations').where('userId', '==', uid).get();
  const canonical = await db.collection('operations').doc(uid).get();
  const workers = new Map(linked.docs.filter(d => d.data()._entity === 'worker').map(d => [d.id, d.ref]));
  if (canonical.exists && canonical.data()?._entity === 'worker') workers.set(canonical.id, canonical.ref);
  const refs = [...workers.values()];
  for (let offset = 0; offset < refs.length; offset += 400) {
    const batch = db.batch();
    for (const ref of refs.slice(offset, offset + 400)) batch.update(ref, {
      isActive: false, isDeleted: true, status: 'deleted', deletedAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
  // Remove private profile subcollections too, including any profile-held tokens.
  await db.recursiveDelete(profileRef);
  try {
    await auth.getUser(uid);
    throw new HttpsError('internal', 'لم يكتمل حذف حساب الدخول.');
  } catch (error) { if (!notFound(error)) throw error; }
  if ((await profileRef.get()).exists) throw new HttpsError('internal', 'لم يكتمل حذف ملف المستخدم.');
  const auditRef = db.collection('audit').doc(`permanent-delete-${uid}`);
  await db.runTransaction(async tx => {
    const audit = await tx.get(auditRef);
    tx.set(jobRef, { status: 'completed', completedAt: FieldValue.serverTimestamp() }, { merge: true });
    if (!audit.exists) tx.set(auditRef, {
      actorId, targetId: uid, operation: 'PERMANENT_DELETE_USER',
      before: { name: metadata.name ?? '', role: metadata.role ?? '' },
      after: { authDeleted: true, profileDeleted: true, workerProjectionsRemoved: refs.length, historyPreserved: true },
      createdAt: new Date().toISOString(), timestamp: FieldValue.serverTimestamp(), immutable: true,
    });
  });
  return { ok: true, userId: uid, deletedProfile: true, deletedAuth: true,
    alreadyAbsent: !profile.exists && !authBefore, historyPreserved: true };
}
