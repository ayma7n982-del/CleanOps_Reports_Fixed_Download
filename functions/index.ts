import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { readSmsCredentials, smsProviderStatus, configureTwilioCredentials } from './sms_provider';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, FieldValue, DocumentReference, DocumentData, Timestamp } from 'firebase-admin/firestore';
import { randomBytes } from 'crypto';

initializeApp();
const db = getFirestore();
const auth = getAuth();

const MANAGEMENT_ROLES = ['donor_manager', 'jsc_coordinator', 'municipality_coordinator'] as const;
const WORKFORCE_ROLES = ['worker', 'group_supervisor'] as const;
type Role = typeof MANAGEMENT_ROLES[number] | typeof WORKFORCE_ROLES[number];

function isManagementRole(role: string): role is typeof MANAGEMENT_ROLES[number] {
  return (MANAGEMENT_ROLES as readonly string[]).includes(role);
}

function isWorkforceRole(role: string): role is typeof WORKFORCE_ROLES[number] {
  return (WORKFORCE_ROLES as readonly string[]).includes(role);
}

async function requireActor(uid: string) {
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) throw new HttpsError('permission-denied', 'Actor profile is missing.');
  const actor = snap.data() ?? {};
  if (actor.isActive === false) throw new HttpsError('permission-denied', 'Actor account is inactive.');
  return actor;
}

export const resolveLoginEmail = onCall({ region: 'us-central1' }, async (request) => {
  const raw = String((request.data as Record<string, unknown> | undefined)?.username ?? '').trim().toLowerCase();
  if (!raw) throw new HttpsError('invalid-argument', 'Username is required.');
  if (raw.includes('@')) return { email: raw };
  const snap = await db.collection('users')
    .where('username', '==', raw)
    .limit(1)
    .get();
  if (snap.empty) {
    return { email: `${raw}@solidwaste.local` };
  }
  const data = snap.docs[0].data();
  const email = String(data.email ?? '').trim().toLowerCase();
  return { email: email || `${raw}@solidwaste.local` };
});

export const requestPasswordReset = onCall({ region: 'us-central1' }, async (request) => {
  const raw = String((request.data as Record<string, unknown> | undefined)?.username ?? '').trim().toLowerCase();
  if (!raw) throw new HttpsError('invalid-argument', 'Username is required.');
  let email = raw.includes('@') ? raw : '';
  if (!email) {
    const snap = await db.collection('users')
      .where('username', '==', raw)
      .limit(1)
      .get();
    if (!snap.empty) {
      const profile = snap.docs[0];
      const data = profile.data();
      email = String(data.email ?? '').trim().toLowerCase();
      if (!email) {
        try {
          const authProfile = await auth.getUser(profile.id);
          email = String(authProfile.email ?? '').trim().toLowerCase();
        } catch (_) {}
      }
    }
    if (!email) email = `${raw}@solidwaste.local`;
  }

  let authUser;
  try {
    authUser = await auth.getUserByEmail(email);
  } catch (e: any) {
    if (e?.code === 'auth/user-not-found') {
      return { sent: true };
    }
    throw new HttpsError('internal', 'Unable to check the account.');
  }

  if (authUser.disabled) return { sent: true };

  const apiKey = process.env.FIREBASE_WEB_API_KEY ?? 'AIzaSyAa8b1275kDi-xxkiDbKVSOD8U0FvmTJBc';
  const response = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${encodeURIComponent(apiKey)}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ requestType: 'PASSWORD_RESET', email }),
  });

  if (!response.ok) {
    const body = await response.text();
    console.error('Password reset delivery failed:', body);
    throw new HttpsError('failed-precondition', 'Password reset email could not be sent.');
  }
  return { sent: true };
});

export const provisionWorkforceUser = onCall({ region: 'us-central1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const actor = await requireActor(request.auth.uid);
  if (actor.role !== 'municipality_coordinator') {
    throw new HttpsError('permission-denied', 'Only the Municipality Coordinator may provision workforce accounts.');
  }
  const data = request.data as Record<string, unknown>;
  return createUserAccount({
    actorUid: request.auth.uid,
    actorRole: String(actor.role),
    data,
    allowedRoles: WORKFORCE_ROLES,
  });
});

export const provisionManagementUser = onCall({ region: 'us-central1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const actor = await requireActor(request.auth.uid);
  if (actor.role !== 'donor_manager') {
    throw new HttpsError('permission-denied', 'Only Level 4 may provision management accounts.');
  }
  const data = request.data as Record<string, unknown>;
  const role = String(data.role ?? '');
  if (!isManagementRole(role)) {
    throw new HttpsError('invalid-argument', 'Only Level 2, Level 3, or Level 4 accounts may be created here.');
  }
  return createUserAccount({
    actorUid: request.auth.uid,
    actorRole: String(actor.role),
    data,
    allowedRoles: MANAGEMENT_ROLES,
  });
});

async function createUserAccount({
  actorUid,
  actorRole,
  data,
  allowedRoles,
}: {
  actorUid: string;
  actorRole: string;
  data: Record<string, unknown>;
  allowedRoles: readonly Role[];
}) {
  const name = String(data.name ?? '').trim();
  const username = String(data.username ?? '').trim().toLowerCase();
  const role = String(data.role ?? '') as Role;
  const phone = String(data.phone ?? '').trim();
  const requestedEmail = String(data.email ?? '').trim().toLowerCase();
  const employeeId = String(data.employeeId ?? '').trim();
  const jobTitle = String(data.jobTitle ?? '').trim();
  const notes = String(data.notes ?? '').trim();
  const requestedPassword = String(data.password ?? '');
  const scope = String(data.scope ?? 'assigned_only');
  const cycleId = String(data.cycleId ?? '').trim();
  const groupId = String(data.groupId ?? '').trim();

  if (!name || !username || !allowedRoles.includes(role)) {
    throw new HttpsError('invalid-argument', 'Incomplete account data.');
  }
  if (isWorkforceRole(role) && (!cycleId || !groupId)) {
    throw new HttpsError('invalid-argument', 'Workforce accounts require cycleId and groupId.');
  }
  if (cycleId) {
    const cycle = await db.collection('work_cycles').doc(cycleId).get();
    if (!cycle.exists || cycle.data()?.status !== 'active') {
      throw new HttpsError('failed-precondition', 'The selected work cycle is not active.');
    }
  }

  const email = requestedEmail || (username.includes('@') ? username : `${username}@solidwaste.local`);
  const temporaryPassword = requestedPassword || generatePassword();
  if (temporaryPassword.length < 8) throw new HttpsError('invalid-argument', 'Password must be at least 8 characters.');
  let authUser;
  try {
    authUser = await auth.createUser({
      email,
      password: temporaryPassword,
      displayName: name,
      phoneNumber: phone || undefined,
      disabled: false,
    });
  } catch (e: any) {
    if (e?.code === 'auth/email-already-exists') throw new HttpsError('already-exists', 'Username already exists.');
    throw new HttpsError('internal', e?.message ?? 'Unable to create account.');
  }

  try {
    const userRef = db.collection('users').doc(authUser.uid);
    const auditRef = db.collection('audit').doc();
    const batch = db.batch();
    batch.set(userRef, {
      id: authUser.uid,
      username: username.replace(/@solidwaste\.local$/i, ''),
      email: authUser.email,
      name,
      role,
      scope,
      phone,
      employeeId,
      jobTitle,
      notes,
      groupId: groupId || null,
      municipalityCoordinatorId: isWorkforceRole(role) && actorRole === 'municipality_coordinator' ? actorUid : null,
      cycleId: cycleId || null,
      isActive: true,
      status: 'active',
      createdBy: actorUid,
      createdByRole: actorRole,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.set(auditRef, {
      actorId: actorUid,
      operation: 'PROVISION_USER',
      targetId: authUser.uid,
      after: { username, role, cycleId: cycleId || null, groupId: groupId || null },
      createdAt: new Date().toISOString(),
      timestamp: FieldValue.serverTimestamp(),
      immutable: true,
    });
    await batch.commit();
  } catch (e: any) {
    await auth.deleteUser(authUser.uid).catch(() => undefined);
    throw new HttpsError('internal', e?.message ?? 'Unable to create user profile and audit record.');
  }

  return { uid: authUser.uid, username: username.replace(/@solidwaste\.local$/i, ''), email, temporaryPassword, passwordWasProvided: requestedPassword.length > 0, role };
}



export const deleteManagedUser = onCall({ region: 'us-central1', timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const actorUid = request.auth.uid;
  const actor = await requireActor(actorUid);
  const userId = String(request.data?.userId ?? '').trim();
  if (!userId) throw new HttpsError('invalid-argument', 'userId is required.');
  if (userId === actorUid) throw new HttpsError('failed-precondition', 'لا يمكن حذف الحساب الحالي.');

  const targetRef = db.collection('users').doc(userId);
  const targetSnap = await targetRef.get();
  const target = targetSnap.exists ? (targetSnap.data() ?? {}) : null;
  let authTargetExists = true;
  let authTarget: Awaited<ReturnType<typeof auth.getUser>> | null = null;
  try {
    authTarget = await auth.getUser(userId);
  } catch (e: any) {
    if (e?.code === 'auth/user-not-found') authTargetExists = false;
    else throw new HttpsError('internal', e?.message ?? 'تعذر التحقق من حساب Firebase Authentication.');
  }

  // A municipality coordinator may only delete workforce users explicitly
  // assigned to them. Only the manager may repair/delete orphaned Auth accounts
  // whose Firestore profile has already gone missing.
  const targetRole = String(target?.role ?? '');
  const workforce = targetRole === 'worker' || targetRole === 'group_supervisor';
  const allowed = actor.role === 'donor_manager'
    || (actor.role === 'municipality_coordinator' && target !== null && workforce
      && String(target.municipalityCoordinatorId ?? '') === actorUid);
  if (!allowed) throw new HttpsError('permission-denied', 'لا تملك صلاحية حذف هذا المستخدم.');

  // Idempotent cleanup: a stale Firestore row, a stale Auth account, or a
  // previous partially-completed deletion must not trap the admin in "not found".
  // We retain operational history; only the account/profile are removed.
  if (authTargetExists) {
    try {
      await auth.deleteUser(userId);
    } catch (e: any) {
      if (e?.code !== 'auth/user-not-found') {
        throw new HttpsError('internal', e?.message ?? 'تعذر حذف حساب Firebase Authentication.');
      }
      authTargetExists = false;
    }
  }
  if (targetSnap.exists) await targetRef.delete();

  // Confirm the account and profile are absent before acknowledging success.
  const remainingProfile = await targetRef.get();
  let remainingAuth = false;
  try {
    await auth.getUser(userId);
    remainingAuth = true;
  } catch (e: any) {
    if (e?.code !== 'auth/user-not-found') {
      throw new HttpsError('internal', e?.message ?? 'تعذر التحقق من حذف حساب الدخول.');
    }
  }
  if (remainingProfile.exists || remainingAuth) {
    throw new HttpsError('internal', 'لم يكتمل حذف المستخدم من Firebase. يرجى إعادة المحاولة.');
  }

  await db.collection('audit').add({
    actorId: actorUid,
    operation: 'DELETE_USER',
    targetId: userId,
    before: { name: String(target?.name ?? authTarget?.displayName ?? ''), role: targetRole || 'unknown', profileExisted: targetSnap.exists, authExisted: authTargetExists },
    after: { profileDeleted: targetSnap.exists, authDeleted: authTargetExists, idempotentCleanup: !targetSnap.exists && !authTargetExists },
    createdAt: new Date().toISOString(),
    timestamp: FieldValue.serverTimestamp(),
    immutable: true,
  });
  return { ok: true, userId, deletedProfile: targetSnap.exists, deletedAuth: authTargetExists, alreadyAbsent: !targetSnap.exists && !authTargetExists };
});

export const recordAttendanceCheckout = onCall({ region: 'us-central1', timeoutSeconds: 30 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const uid = request.auth.uid;
  const actor = await requireActor(uid);
  if (String(actor.role ?? '') !== 'group_supervisor') {
    throw new HttpsError('permission-denied', 'تسجيل الانصراف متاح لمشرف المجموعة فقط.');
  }
  const attendanceId = String(request.data?.attendanceId ?? '').trim();
  if (!attendanceId) throw new HttpsError('invalid-argument', 'attendanceId is required.');
  const ref = db.collection('operations').doc(attendanceId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'سجل الحضور غير موجود.');
  const row = snap.data() ?? {};
  if (String(row._entity ?? '') !== 'attendance') throw new HttpsError('failed-precondition', 'السجل المحدد ليس سجل حضور.');
  const groupId = String(actor.groupId ?? '').trim();
  if (!groupId || String(row.groupId ?? row.groupName ?? '').trim() !== groupId) {
    throw new HttpsError('permission-denied', 'لا يمكنك تسجيل الانصراف خارج مجموعتك.');
  }
  const status = String(row.status ?? '');
  if (!['present', 'حضور'].includes(status)) throw new HttpsError('failed-precondition', 'لا يمكن تسجيل الانصراف إلا لسجل حضور.');
  if (row.checkOutAt || row.checkOutTime) return { ok: true, attendanceId, alreadyRecorded: true, checkOutAt: row.checkOutAt ?? null };
  const now = new Date();
  const checkOutAt = now.toISOString();
  await ref.set({ checkOutAt, checkOutTime: now.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', hour12: false }), checkoutRecordedBy: uid, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  await db.collection('audit').add({
    actorId: uid,
    operation: 'ATTENDANCE_CHECKOUT_RECORDED',
    targetId: attendanceId,
    before: { checkOutAt: null },
    after: { workerId: String(row.workerId ?? ''), checkOutAt },
    createdAt: checkOutAt,
    timestamp: FieldValue.serverTimestamp(),
    immutable: true,
  });
  return { ok: true, attendanceId, alreadyRecorded: false, checkOutAt };
});


/**
 * Operational report writes go through Admin SDK so the existing Firestore
 * rules stay unchanged. This function enforces the same role/scope checks and
 * keeps the report lifecycle auditable.
 */
export const saveOperationalReport = onCall({ region: 'us-central1', timeoutSeconds: 60 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const uid = request.auth.uid;
  const actor = await requireActor(uid);
  const input = request.data as Record<string, unknown>;
  const sourceEntity = String(input.sourceEntity ?? '').trim();
  const operation = String(input.operation ?? 'create').trim();
  const report = (input.report ?? {}) as Record<string, unknown>;
  const reportId = String(report.id ?? '').trim();
  if (!reportId || !['work_report', 'report_approval'].includes(sourceEntity)) {
    throw new HttpsError('invalid-argument', 'Invalid operational report payload.');
  }

  const reportRef = db.collection('operations').doc(reportId);
  const existingSnap = await reportRef.get();
  const existing = existingSnap.exists ? (existingSnap.data() ?? {}) : null;
  const actorRole = String(actor.role ?? '');
  const actorGroup = String(actor.groupId ?? '').trim();
  const actorScope = String(actor.scope ?? '').trim();
  const reportGroup = String(report.groupId ?? existing?.groupId ?? '').trim();
  const reportMunicipality = String(report.municipalityName ?? report.municipality ?? existing?.municipalityName ?? existing?.municipality ?? '').trim();
  const coordinatorId = String(report.municipalityCoordinatorId ?? existing?.municipalityCoordinatorId ?? '').trim();
  const reporterId = String(report.reportedBy ?? report.requestedBy ?? existing?.reportedBy ?? existing?.requestedBy ?? '').trim();
  const isScopedMunicipality = actorScope.length > 0 && actorScope !== 'all' && actorScope !== 'assigned_only' && reportMunicipality === actorScope;

  if (operation === 'create') {
    if (existingSnap.exists) throw new HttpsError('already-exists', 'يوجد تقرير بهذا المعرّف مسبقًا.');
    if (sourceEntity === 'work_report') {
      if (!['municipality_coordinator', 'group_supervisor'].includes(actorRole)) {
        throw new HttpsError('permission-denied', 'لا تملك صلاحية إنشاء تقرير عمل.');
      }
      if (reporterId !== uid) throw new HttpsError('permission-denied', 'يجب أن يكون منشئ التقرير هو المستخدم الحالي.');
      if (actorRole === 'group_supervisor' && (!actorGroup || reportGroup !== actorGroup)) {
        throw new HttpsError('permission-denied', 'لا يمكنك إنشاء تقرير خارج مجموعتك.');
      }
      if (actorRole === 'municipality_coordinator' && coordinatorId !== uid && !isScopedMunicipality) {
        throw new HttpsError('permission-denied', 'التقرير خارج نطاق البلدية المخصصة لك.');
      }
      if (String(report.status ?? 'draft') !== 'draft') throw new HttpsError('failed-precondition', 'يجب حفظ تقرير العمل كمسودة أولاً.');
    } else {
      if (actorRole !== 'municipality_coordinator' || String(report.requestedBy ?? '') !== uid) {
        throw new HttpsError('permission-denied', 'لا تملك صلاحية إرسال هذا التقرير للمراجعة.');
      }
      if (coordinatorId !== uid && !isScopedMunicipality) {
        throw new HttpsError('permission-denied', 'التقرير خارج نطاق البلدية المخصصة لك.');
      }
      if (String(report.status ?? '') !== 'submitted') throw new HttpsError('failed-precondition', 'يجب إرسال التقرير للمراجعة.');
    }
  } else if (operation === 'update') {
    if (!existingSnap.exists) throw new HttpsError('not-found', 'التقرير غير موجود أو حُذف.');
    const current = existing!;
    const currentKind = String(current.reportKind ?? sourceEntity);
    if (currentKind !== sourceEntity) throw new HttpsError('failed-precondition', 'نوع التقرير لا يطابق السجل المحفوظ.');
    const oldStatus = String(current.status ?? 'draft');
    const newStatus = String(report.status ?? oldStatus);
    const ownerId = String(current.reportedBy ?? current.requestedBy ?? '');
    if (sourceEntity === 'work_report' && (actorRole === 'group_supervisor' || actorRole === 'municipality_coordinator')
      && ownerId === uid && oldStatus === 'draft' && newStatus === 'submitted') {
      if (actorRole === 'group_supervisor' && (!actorGroup || String(current.groupId ?? '') !== actorGroup)) {
        throw new HttpsError('permission-denied', 'لا يمكنك إرسال تقرير خارج مجموعتك.');
      }
      if (actorRole === 'municipality_coordinator' && String(current.municipalityCoordinatorId ?? '') !== uid
        && !(actorScope && actorScope !== 'all' && actorScope !== 'assigned_only' && String(current.municipalityName ?? '') === actorScope)) {
        throw new HttpsError('permission-denied', 'التقرير خارج نطاق البلدية المخصصة لك.');
      }
    } else if (actorRole === 'jsc_coordinator' && oldStatus === 'submitted' && ['approved', 'needs_edits'].includes(newStatus)) {
      const currentCouncil = String(current.councilName ?? current.councilId ?? current.municipalityName ?? '');
      if (actorScope && actorScope !== 'all' && actorScope !== 'assigned_only' && currentCouncil !== actorScope) {
        throw new HttpsError('permission-denied', 'التقرير خارج نطاق المجلس المخصص لك.');
      }
    } else if (actorRole === 'donor_manager' && oldStatus === 'approved' && newStatus === 'closed') {
      // Manager closes only reports that have passed council approval.
    } else {
      throw new HttpsError('permission-denied', 'إجراء الاعتماد غير مسموح في هذه المرحلة.');
    }
  } else {
    throw new HttpsError('invalid-argument', 'Unsupported report operation.');
  }

  const now = new Date().toISOString();
  const normalized: Record<string, unknown> = {
    ...(existing ?? {}), ...report,
    id: reportId,
    _entity: 'report',
    reportKind: sourceEntity,
    updatedBy: uid,
    updatedAt: FieldValue.serverTimestamp(),
    ...(operation === 'create' ? { createdAt: report.createdAt ?? now, createdBy: uid } : {}),
    ...(operation === 'update' && report.status ? { statusChangedAt: now, statusChangedBy: uid, statusChangedByRole: actorRole } : {}),
  };
  await reportRef.set(normalized, { merge: true });
  await db.collection('audit').add({
    actorId: uid,
    operation: operation === 'create' ? 'CREATE_OPERATIONAL_REPORT' : 'OPERATIONAL_REPORT_STATUS_CHANGED',
    targetId: reportId,
    before: existing ? { status: existing.status ?? 'draft' } : {},
    after: { status: normalized.status ?? 'draft', reportKind: sourceEntity, actorRole },
    createdAt: now,
    timestamp: FieldValue.serverTimestamp(),
    immutable: true,
  });
  return { ok: true, id: reportId, status: normalized.status ?? 'draft', reportKind: sourceEntity };
});


// ---------------------------------------------------------------------------
// TEMPORARY CYCLE 11 SIMULATION SEEDER
// ---------------------------------------------------------------------------
// This seeder is intentionally isolated from the normal application write
// paths. Every document created by the simulation is tagged with
// `isSimulation: true`, which makes cleanup safe and deterministic.
const SIMULATION_FLAG = true;
const SIMULATION_PLACEHOLDER_IMAGE = 'https://via.placeholder.com/150';

function simulationBase(extra: Record<string, unknown> = {}) {
  return {
    isSimulation: SIMULATION_FLAG,
    simulationName: 'Cycle 11 • Bani Suheila • October 2026',
    ...extra,
  };
}

export const runCycle11Simulation = onCall({ region: 'us-central1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const actor = await requireActor(request.auth.uid);
  if (actor.role !== 'donor_manager') {
    throw new HttpsError('permission-denied', 'Only Level 4 may run the temporary simulation.');
  }

  // Prevent duplicate seed runs. The function is temporary and should never
  // silently create a second simulation set.
  const existing = await db.collection('work_cycles')
    .where('isSimulation', '==', true)
    .limit(100)
    .get();
  if (existing.docs.some((doc) => doc.data().cycleNumber === 11)) {
    throw new HttpsError('already-exists', 'بيانات محاكاة الدورة 11 موجودة مسبقاً. احذفها أولاً ثم أعد التشغيل.');
  }

  const municipalityId = 'sim_municipality_bani_suheila';
  const cycleId = 'sim_cycle_11_oct_2026';
  const municipalityName = 'بلدية بني سهيلا';
  // If a real L2 account for Bani Suheila exists, bind the simulation to it
  // so the same data is visible from the municipality dashboard under the
  // existing read rules. Otherwise keep the simulation isolated.
  const requestedCoordinatorId = String(request.data?.municipalityCoordinatorId ?? '').trim();
  let targetCoordinatorId = requestedCoordinatorId;
  if (!targetCoordinatorId) {
    const candidate = await db.collection('users')
      .where('role', '==', 'municipality_coordinator')
      .limit(100).get();
    const match = candidate.docs.find((d) => String(d.data().municipalityName ?? d.data().scope ?? '').trim() === municipalityName);
    if (match) targetCoordinatorId = match.id;
  }
  const accessMunicipalityId = targetCoordinatorId || municipalityId;
  const startDate = new Date('2026-10-01T00:00:00+03:00');
  const endDate = new Date('2026-10-20T23:59:59+03:00');

  const dumpsites = [
    {
      id: 'sim_dumpsite_asdaa',
      nameAr: 'مكب أصداء',
      nameEn: 'Asdaa',
      capacity: 20,
      fillPercentage: 0,
    },
    {
      id: 'sim_dumpsite_al_aqsa',
      nameAr: 'مكب الأقصى',
      nameEn: 'Al-Aqsa',
      capacity: 20,
      fillPercentage: 0,
    },
  ];

  const groups = Array.from({ length: 5 }, (_, index) => {
    const n = index + 1;
    return { id: `sim_cycle11_group_${String(n).padStart(2, '0')}`, number: n, name: `المجموعة ${n}` };
  });

  const writes: Array<{ ref: DocumentReference; data: DocumentData }> = [];
  const add = (ref: DocumentReference, data: DocumentData) => {
    writes.push({ ref, data: simulationBase(data) });
  };

  // 1) Municipality.
  add(db.collection('municipalities').doc(municipalityId), {
    id: municipalityId,
    name: municipalityName,
    nameAr: municipalityName,
    nameEn: 'Bani Suheila Municipality',
    status: 'active',
    createdAt: FieldValue.serverTimestamp(),
  });
  // Mirror the municipality into the existing operations stream so the app
  // can display simulation municipalities without opening a new Firestore
  // rule surface for the municipalities collection.
  add(db.collection('operations').doc('sim_cycle11_municipality_index'), {
    id: 'sim_cycle11_municipality_index',
    _entity: 'municipality',
    name: municipalityName,
    nameAr: municipalityName,
    nameEn: 'Bani Suheila Municipality',
    municipalityId,
    municipalityName,
    status: 'active',
    createdAt: FieldValue.serverTimestamp(),
  });

  // 2) Cycle 11 — October 2026.
  add(db.collection('work_cycles').doc(cycleId), {
    id: cycleId,
    name: 'الدورة 11 - أكتوبر 2026',
    cycleNumber: 11,
    month: 10,
    monthName: 'أكتوبر 2026',
    startDate,
    endDate,
    status: 'active',
    municipalityId,
    municipalityName,
    createdBy: request.auth.uid,
    createdAt: FieldValue.serverTimestamp(),
  });
  add(db.collection('operations').doc('sim_cycle11_cycle_index'), {
    id: 'sim_cycle11_cycle_index',
    _entity: 'cycle',
    name: 'الدورة 11 - أكتوبر 2026',
    cycleNumber: 11,
    month: 10,
    monthName: 'أكتوبر 2026',
    cycleId,
    municipalityId,
    municipalityName,
    status: 'active',
    startDate: startDate.toISOString(),
    endDate: endDate.toISOString(),
    createdAt: startDate.toISOString(),
  });

  // 3) Dumpsites.
  for (const site of dumpsites) {
    add(db.collection('dumpsites').doc(site.id), {
      id: site.id,
      name: site.nameAr,
      nameAr: site.nameAr,
      nameEn: site.nameEn,
      code: site.nameEn.toUpperCase().replace(/[^A-Z]/g, ''),
      location: municipalityName,
      capacity: site.capacity,
      fillPercentage: site.fillPercentage,
      isActive: true,
      municipalityId: accessMunicipalityId,
      sourceMunicipalityId: municipalityId,
      municipalityName,
      createdBy: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }

  // 4) Five containers.
  const containerCoordinates = [
    [31.3475, 34.3042],
    [31.3490, 34.3061],
  ];
  for (let i = 0; i < 2; i++) {
    const id = `sim_cycle11_container_${String(i + 1).padStart(2, '0')}`;
    add(db.collection('containers').doc(id), {
      id,
      locationName: 'شارع الرشيد، خان يونس',
      gpsCoordinates: { lat: containerCoordinates[i][0], lng: containerCoordinates[i][1] },
      latitude: containerCoordinates[i][0],
      longitude: containerCoordinates[i][1],
      status: 'empty',
      issueStatus: 'none',
      municipalityId: accessMunicipalityId,
      municipalityName,
      sourceMunicipalityId: municipalityId,
      groupId: groups[i].id,
      groupName: groups[i].name,
      feedbackNotes: '',
      imageUrl: SIMULATION_PLACEHOLDER_IMAGE,
      imageUrls: [SIMULATION_PLACEHOLDER_IMAGE],
      updatedAt: new Date().toISOString(),
      updatedBy: request.auth.uid,
      createdAt: new Date().toISOString(),
    });
  }

  // 5) Groups + workers. Simulation workers are Firestore-only profiles;
  // no Firebase Authentication accounts are created.
  for (const group of groups) {
    add(db.collection('operations').doc(group.id), {
      id: group.id,
      _entity: 'group',
      name: group.name,
      groupName: group.name,
      groupNumber: group.number,
      number: group.number,
      status: 'active',
      municipalityId: accessMunicipalityId,
      municipalityName,
      municipalityCoordinatorId: targetCoordinatorId || 'simulation',
      cycleId,
      cycleName: 'الدورة 11 - أكتوبر 2026',
      createdBy: request.auth.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    const supervisorId = `sim_cycle11_group${group.number}_supervisor`;
    add(db.collection('users').doc(supervisorId), {
      id: supervisorId,
      username: supervisorId,
      email: `${supervisorId}@simulation.cleanops.local`,
      name: `مشرف ميداني ${group.number}`,
      role: 'group_supervisor',
      scope: municipalityName,
      groupId: group.id,
      groupName: group.name,
      municipalityCoordinatorId: targetCoordinatorId || 'simulation',
      municipalityName,
      cycleId,
      cycleName: 'الدورة 11 - أكتوبر 2026',
      isActive: true,
      status: 'active',
      jobTitle: 'مشرف ميداني',
      employeeId: `SIM-G${group.number}-SUP`,
      notes: 'حساب محاكاة - لا يملك Firebase Authentication.',
      createdBy: request.auth.uid,
      createdByRole: actor.role,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    for (let w = 1; w <= 7; w++) {
      const workerId = `sim_cycle11_group${group.number}_collector${String(w).padStart(2, '0')}`;
      add(db.collection('users').doc(workerId), {
        id: workerId,
        username: workerId,
        email: `${workerId}@simulation.cleanops.local`,
        name: `عامل جمع أساسي ${group.number}-${w}`,
        role: 'worker',
        scope: municipalityName,
        groupId: group.id,
        groupName: group.name,
        municipalityCoordinatorId: targetCoordinatorId || 'simulation',
        municipalityName,
        cycleId,
        isActive: true,
        status: 'active',
        jobTitle: 'عامل جمع أساسي',
        employeeId: `SIM-G${group.number}-W${String(w).padStart(2, '0')}`,
        notes: 'حساب محاكاة - لا يملك Firebase Authentication.',
        createdBy: request.auth.uid,
        createdByRole: actor.role,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    for (let w = 1; w <= 2; w++) {
      const workerId = `sim_cycle11_group${group.number}_animalcart${w}`;
      add(db.collection('users').doc(workerId), {
        id: workerId,
        username: workerId,
        email: `${workerId}@simulation.cleanops.local`,
        name: `عامل كارة بحمار ${group.number}-${w}`,
        role: 'worker',
        scope: municipalityName,
        groupId: group.id,
        groupName: group.name,
        municipalityCoordinatorId: targetCoordinatorId || 'simulation',
        municipalityName,
        cycleId,
        isActive: true,
        status: 'active',
        jobTitle: 'عامل كارة بحمار',
        employeeId: `SIM-G${group.number}-A${w}`,
        notes: 'حساب محاكاة - لا يملك Firebase Authentication.',
        createdBy: request.auth.uid,
        createdByRole: actor.role,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  }

  // 6) Trips: 20 days. Group 1 = 5/day, then +2 trips for each next group.
  // Each cart trip carries 10 tons; GPS and placeholder photos are attached.
  let tripSequence = 0;
  for (let day = 0; day < 20; day++) {
    const tripDate = new Date(startDate.getTime() + day * 24 * 60 * 60 * 1000);
    for (const group of groups) {
      const dailyTrips = 5 + (group.number - 1) * 2;
      for (let t = 1; t <= dailyTrips; t++) {
        tripSequence++;
        const destination = Math.random() < 0.5 ? dumpsites[0] : dumpsites[1];
        const tripId = `sim_cycle11_trip_${String(tripSequence).padStart(4, '0')}`;
        const supervisorId = `sim_cycle11_group${group.number}_supervisor`;
        add(db.collection('operations').doc(tripId), {
          id: tripId,
          _entity: 'trip',
          title: `نقلة ${tripSequence}`,
          operation: 'trip',
          status: 'completed',
          tripNumber: t,
          tripSequence,
          date: tripDate.toISOString(),
          createdAt: tripDate.toISOString(),
          municipalityId,
          municipalityName,
          cycleId,
          cycleName: 'الدورة 11 - أكتوبر 2026',
          groupId: group.id,
          groupName: group.name,
          supervisorId,
          supervisorName: `مشرف ميداني ${group.number}`,
          sourceLocation: 'شارع الرشيد، خان يونس',
          destinationDumpsiteId: destination.id,
          destinationDumpsiteName: destination.nameAr,
          destination: destination.nameAr,
          volumeTons: 10,
          estimatedQuantity: 10,
          unit: 'طن',
          cartType: 'animal_cart',
          alternative: true,
          gpsCoordinates: { lat: 31.3475 + (group.number * 0.001) + (day * 0.0001), lng: 34.3042 + (t * 0.0001) },
          latitude: 31.3475 + (group.number * 0.001) + (day * 0.0001),
          longitude: 34.3042 + (t * 0.0001),
          imageUrls: [SIMULATION_PLACEHOLDER_IMAGE],
          imageUrl: SIMULATION_PLACEHOLDER_IMAGE,
          notes: 'نقلة محاكاة للدورة 11.',
          createdBy: request.auth.uid,
        });
      }
    }
  }

  // Firestore batch limit is 500. The current seed is below that limit, but
  // chunking keeps this temporary utility safe if the dataset grows later.
  for (let i = 0; i < writes.length; i += 450) {
    const batch = db.batch();
    for (const item of writes.slice(i, i + 450)) batch.set(item.ref, item.data);
    await batch.commit();
  }

  return {
    ok: true,
    isSimulation: true,
    municipality: municipalityName,
    cycleId,
    cycleNumber: 11,
    days: 20,
    groups: groups.length,
    supervisors: groups.length,
    primaryWorkers: groups.length * 7,
    animalCartWorkers: groups.length * 2,
    containers: 2,
    dumpsites: 2,
    trips: tripSequence,
    volumeTons: tripSequence,
  };
});

export const deleteSimulationData = onCall({ region: 'us-central1', timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication is required.');
  const actor = await requireActor(request.auth.uid);
  if (actor.role !== 'donor_manager') {
    throw new HttpsError('permission-denied', 'Only Level 4 may delete simulation data.');
  }

  let deleted = 0;
  const collections = await db.listCollections();
  for (const collection of collections) {
    while (true) {
      const snap = await collection.where('isSimulation', '==', true).limit(450).get();
      if (snap.empty) break;
      const batch = db.batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      deleted += snap.size;
      if (snap.size < 450) break;
    }
  }

  return { ok: true, deleted, isSimulationCleanup: true };
});

export const syncAiUserState = onDocumentWritten('users/{uid}', async (event) => {
  const before = event.data?.before.exists ? (event.data.before.data() ?? {}) : null;
  const after = event.data?.after.exists ? (event.data.after.data() ?? {}) : null;
  if (!before && !after) return;
  const ref = db.collection('ai_state').doc('command_center');
  const updates: Record<string, unknown> = {
    updatedAt: FieldValue.serverTimestamp(),
    lastUserEvent: {
      uid: event.params.uid,
      action: before && after ? 'updated' : after ? 'created' : 'deleted',
      role: after?.role ?? before?.role ?? null,
      isActive: after?.isActive !== false,
    },
  };
  if (!before && after) {
    updates.totalUsers = FieldValue.increment(1);
    updates.activeUsers = FieldValue.increment(after.isActive === false ? 0 : 1);
    if (after.role) updates[`roles.${String(after.role)}`] = FieldValue.increment(1);
  } else if (before && !after) {
    updates.totalUsers = FieldValue.increment(-1);
    updates.activeUsers = FieldValue.increment(before.isActive === false ? 0 : -1);
    if (before.role) updates[`roles.${String(before.role)}`] = FieldValue.increment(-1);
  } else if (before && after) {
    const beforeActive = before.isActive !== false;
    const afterActive = after.isActive !== false;
    if (beforeActive !== afterActive) updates.activeUsers = FieldValue.increment(afterActive ? 1 : -1);
    if (before.role !== after.role) {
      if (before.role) updates[`roles.${String(before.role)}`] = FieldValue.increment(-1);
      if (after.role) updates[`roles.${String(after.role)}`] = FieldValue.increment(1);
    }
  }
  await ref.set(updates, { merge: true });
});

function generatePassword(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#';
  const bytes = randomBytes(12);
  return Array.from(bytes, (b: number) => alphabet[b % alphabet.length]).join('');
}


export const redirectCartAssignment = onCall({ region: 'us-central1' }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Sign in first.');
  const actor = await requireActor(uid);
  if (actor.role !== 'municipality_coordinator') {
    throw new HttpsError('permission-denied', 'Municipality coordinator required.');
  }
  const input = (request.data ?? {}) as Record<string, unknown>;
  const cartId = String(input.cartId ?? '').trim();
  const fromGroupId = String(input.fromGroupId ?? '').trim();
  const toGroupId = String(input.toGroupId ?? '').trim();
  const cartCollection = String(input.cartCollection ?? '').trim();
  const requestId = String(input.requestId ?? '').trim();
  if (!cartId || !fromGroupId || !toGroupId || fromGroupId === toGroupId ||
      !['equipment', 'operations'].includes(cartCollection) || !requestId ||
      !/^[a-zA-Z0-9_-]{1,128}$/.test(requestId)) {
    throw new HttpsError('invalid-argument', 'Invalid cart redirect selection.');
  }
  const cartRef = db.collection(cartCollection).doc(cartId);
  const fromRef = db.collection('operations').doc(fromGroupId);
  const toRef = db.collection('operations').doc(toGroupId);
  const logRef = db.collection('operations').doc(requestId);
  return db.runTransaction(async (tx) => {
    const [cartSnap, fromSnap, toSnap, existing] = await Promise.all([
      tx.get(cartRef), tx.get(fromRef), tx.get(toRef), tx.get(logRef),
    ]);
    if (existing.exists) {
      const log = existing.data() ?? {};
      if (log._entity === 'cart_redirect' && log.requestedBy === uid &&
          log.cartId === cartId && log.fromGroupId === fromGroupId &&
          log.toGroupId === toGroupId && log.cartCollection === cartCollection) {
        return { success: true, alreadyApplied: true };
      }
      throw new HttpsError('already-exists', 'Request ID already used.');
    }
    const cart = cartSnap.data();
    const from = fromSnap.data();
    const to = toSnap.data();
    if (!cart || !from || !to || from._entity !== 'group' || to._entity !== 'group' ||
        from.isDeleted === true || to.isDeleted === true ||
        from.municipalityCoordinatorId !== uid || to.municipalityCoordinatorId !== uid ||
        cart.municipalityCoordinatorId !== uid || cart.isDeleted === true) {
      throw new HttpsError('permission-denied', 'Records are missing or outside municipality.');
    }
    if (cartCollection === 'operations' && !['cart', 'equipment', 'heavy_machinery'].includes(String(cart._entity))) {
      throw new HttpsError('invalid-argument', 'Not a cart record.');
    }
    const kind = [cart.type, cart.category, cart.name, cart.machine].map(v => String(v ?? '').toLowerCase());
    if (!kind.some(v => v.includes('كارة') || v.includes('cart'))) {
      throw new HttpsError('invalid-argument', 'Selected equipment is not a cart.');
    }
    if (String(cart.groupId ?? '') !== fromGroupId) {
      throw new HttpsError('failed-precondition', 'Cart is no longer assigned to the source group.');
    }
    tx.update(cartRef, { groupId: toGroupId, updatedAt: FieldValue.serverTimestamp(), updatedBy: uid });
    tx.create(logRef, {
      id: requestId, _entity: 'cart_redirect', cartId, cartCollection,
      cartEntity: cartCollection === 'equipment' ? 'equipment' : String(cart._entity),
      fromGroupId, toGroupId, municipalityCoordinatorId: uid, requestedBy: uid,
      status: 'applied', createdAt: FieldValue.serverTimestamp(),
    });
    return { success: true, alreadyApplied: false };
  });
});


// External messaging is entirely server-side. Never expose the provider token
// or accept a free-form phone number from a Flutter client.
// Only the owner may configure the provider; recipient scope remains
// enforced by the server for all outbound messages.
export const getSmsProviderStatus = onCall({region: 'us-central1'}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication required.');
  const actor = await requireActor(request.auth.uid);
  if (!isManagementRole(String(actor.role ?? ''))) {
    throw new HttpsError('permission-denied', 'Management access required.');
  }
  return smsProviderStatus();
});

export const configureSmsProvider = onCall({region: 'us-central1'}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication required.');
  const actor = await requireActor(request.auth.uid);
  if (actor.role !== 'donor_manager') {
    throw new HttpsError('permission-denied', 'Only the level-4 administrator can configure SMS.');
  }
  const input = (request.data ?? {}) as Record<string, unknown>;
  await configureTwilioCredentials({
    accountSid: String(input.accountSid ?? '').trim(),
    authToken: String(input.authToken ?? '').trim(),
    from: String(input.from ?? '').trim(),
  });
  await db.collection('sms_provider_audit').add({
    updatedBy: request.auth.uid,
    updatedAt: FieldValue.serverTimestamp(),
    action: 'credentials_rotated',
    // Intentionally no credentials or sender phone in the audit log.
  });
  return { saved: true };
});

export const sendExternalSms = onCall({region: 'us-central1'}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const senderId = request.auth.uid;
  const actor = await requireActor(senderId);
  if (!isManagementRole(String(actor.role ?? ''))) {
    throw new HttpsError('permission-denied', 'Management role required for external messaging.');
  }

  const input = (request.data ?? {}) as Record<string, unknown>;
  const targetUserId = String(input.targetUserId ?? '').trim();
  const content = String(input.content ?? '').trim();
  const requestId = String(input.requestId ?? '').trim();
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(requestId) ||
      !/^[A-Za-z0-9_-]{2,128}$/.test(targetUserId) ||
      content.length < 1 || content.length > 500) {
    throw new HttpsError('invalid-argument', 'Invalid recipient, request identifier or message length.');
  }

  const recipientSnap = await db.collection('users').doc(targetUserId).get();
  if (!recipientSnap.exists) throw new HttpsError('not-found', 'Recipient not found.');
  const recipient = recipientSnap.data() ?? {};
  if (recipient.isActive === false) {
    throw new HttpsError('failed-precondition', 'Recipient is inactive.');
  }
  if (actor.role === 'municipality_coordinator') {
    if (!isWorkforceRole(String(recipient.role ?? '')) ||
        recipient.municipalityCoordinatorId !== senderId) {
      throw new HttpsError('permission-denied', 'Recipient is outside your municipality workforce.');
    }
  } else if (!isManagementRole(String(recipient.role ?? ''))) {
    throw new HttpsError('permission-denied', 'Council and donor messaging targets active management accounts only.');
  }

  const to = String(recipient.phone ?? '').trim();
  if (!/^\+[1-9][0-9]{7,14}$/.test(to)) {
    throw new HttpsError('failed-precondition', 'Recipient needs a verified international-format phone number.');
  }
  const credentials = await readSmsCredentials();
  const sid = credentials.accountSid;
  const token = credentials.authToken;
  const from = credentials.from;
  if (!sid || !token || !/^\+[1-9][0-9]{7,14}$/.test(from)) {
    throw new HttpsError('failed-precondition', 'SMS provider has not been configured securely.');
  }

  // A sender-unique requestId plus an hourly rate limit protects against
  // accidental duplicate sends and runaway costs.
  const logRef = db.collection('external_messages').doc(`${senderId}_${requestId}`);
  const hourKey = new Date().toISOString().slice(0, 13).replace(/[-T:]/g, '');
  const rateRef = db.collection('external_message_limits').doc(`${senderId}_${hourKey}`);
  const created = await db.runTransaction(async (tx) => {
    const [existing, rate] = await Promise.all([tx.get(logRef), tx.get(rateRef)]);
    if (existing.exists) return false;
    const count = Number(rate.data()?.count ?? 0);
    if (count >= 20) throw new HttpsError('resource-exhausted', 'Hourly SMS limit reached.');
    tx.create(logRef, {
      senderId, targetUserId, requestId, content, channel: 'sms',
      status: 'sending', createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    tx.set(rateRef, { count: count + 1, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
  if (!created) {
    const existing = await logRef.get();
    return { requestId, status: String(existing.data()?.status ?? 'sending'),
      duplicate: true };
  }

  try {
    const endpoint = `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(sid)}/Messages.json`;
    const credentials = Buffer.from(`${sid}:${token}`).toString('base64');
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${credentials}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({ To: to, From: from, Body: content }),
    });
    if (!response.ok) {
      await logRef.update({
        status: 'failed', providerHttpStatus: response.status,
        updatedAt: FieldValue.serverTimestamp(),
      });
      throw new HttpsError('unavailable', 'The SMS provider rejected this request.');
    }
    const receipt = (await response.json()) as Record<string, unknown>;
    const providerSid = String(receipt.sid ?? '');
    if (!providerSid) throw new HttpsError('internal', 'Provider did not return a request identifier.');
    await logRef.update({
      status: 'submitted', providerMessageSid: providerSid,
      providerStatus: String(receipt.status ?? 'queued'),
      updatedAt: FieldValue.serverTimestamp(),
    });
    // "submitted" means provider acceptance, NOT handset delivery.
    return { requestId, status: 'submitted', duplicate: false };
  } catch (e) {
    await logRef.update({
      status: 'failed', updatedAt: FieldValue.serverTimestamp(),
    }).catch(() => undefined);
    if (e instanceof HttpsError) throw e;
    throw new HttpsError('unavailable', 'External SMS was not confirmed by the provider.');
  }
});


// A manual status refresh displays the provider's actual delivery result,
// without claiming that "submitted" means "delivered".
export const refreshExternalSmsStatus = onCall({region: 'us-central1'}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Authentication required.');
  const actor = await requireActor(request.auth.uid);
  if (!isManagementRole(String(actor.role ?? ''))) {
    throw new HttpsError('permission-denied', 'Management access required.');
  }
  const id = String((request.data as Record<string, unknown> | undefined)?.messageId ?? '');
  if (!/^[A-Za-z0-9_-]{8,180}$/.test(id)) {
    throw new HttpsError('invalid-argument', 'Invalid message identifier.');
  }
  const ref = db.collection('external_messages').doc(id);
  const snapshot = await ref.get();
  const entry = snapshot.data();
  if (!entry || entry.senderId !== request.auth.uid) {
    throw new HttpsError('permission-denied', 'This SMS record is not yours.');
  }
  const providerId = String(entry.providerMessageSid ?? '');
  if (!/^SM[0-9a-f]{32}$/i.test(providerId)) {
    return {status: String(entry.status ?? 'unknown'), refreshed: false};
  }
  const {accountSid, authToken} = await readSmsCredentials();
  let response;
  try {
    response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${encodeURIComponent(accountSid)}/Messages/${providerId}.json`,
      {headers: {Authorization: `Basic ${Buffer.from(`${accountSid}:${authToken}`).toString('base64')}`},
        signal: AbortSignal.timeout(12000)},
    );
  } catch (_) {
    throw new HttpsError('unavailable', 'SMS provider is temporarily unreachable.');
  }
  if (!response.ok) {
    throw new HttpsError('unavailable', 'SMS delivery status could not be checked.');
  }
  const data = (await response.json()) as Record<string, unknown>;
  const providerStatus = String(data.status ?? 'unknown').toLowerCase();
  const normalized = providerStatus === 'delivered' ? 'delivered'
    : providerStatus === 'undelivered' || providerStatus === 'failed' ? 'failed'
    : providerStatus === 'sent' ? 'sent' : 'submitted';
  await ref.update({
    status: normalized, providerStatus, checkedAt: FieldValue.serverTimestamp(),
  });
  return {status: normalized, refreshed: true};
});

// Scheduling uses the trusted server, not a phone timer that stops when the
// user closes the app. The scheduler re-checks live role and destination scope.
async function validateInternalDestination(
  uid: string, actor: DocumentData, targetGroupId: string, targetUserId: string, type: string,
): Promise<boolean> {
  if (!['info', 'warning', 'emergency'].includes(type)) return false;
  if (actor.isActive === false) return false;
  if (targetUserId) {
    if (targetGroupId !== `__USER__:${targetUserId}`) return false;
    const target = (await db.collection('users').doc(targetUserId).get()).data();
    if (!target || target.isActive === false) return false;
    if (actor.role === 'group_supervisor') {
      return ['info','emergency'].includes(type)
        && actor.municipalityCoordinatorId === targetUserId
        && target.role === 'municipality_coordinator';
    }
    if (actor.role === 'municipality_coordinator') {
      return isWorkforceRole(String(target.role ?? ''))
        && target.municipalityCoordinatorId === uid;
    }
    return isManagementRole(String(actor.role ?? ''))
      && isManagementRole(String(target.role ?? ''));
  }
  if (actor.role === 'group_supervisor') {
    return ['info','emergency'].includes(type)
      && typeof actor.groupId === 'string'
      && actor.groupId.length > 0 && actor.groupId === targetGroupId;
  }
  if (actor.role === 'municipality_coordinator') {
    const group = (await db.collection('operations').doc(targetGroupId).get()).data();
    return targetGroupId === '__JSC__' ||
      (!!group && group._entity === 'group' && group.isDeleted !== true &&
       group.municipalityCoordinatorId === uid);
  }
  return ['donor_manager','jsc_coordinator'].includes(String(actor.role ?? ''))
    && targetGroupId === '__ALL_MUNICIPALITIES__';
}

export const scheduleInternalMessage = onCall({ region: 'us-central1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  const uid = request.auth.uid;
  const actor = await requireActor(uid);
  const input = (request.data ?? {}) as Record<string, unknown>;
  const content = String(input.content ?? '').trim();
  const type = String(input.type ?? '');
  const targetUserId = String(input.targetUserId ?? '').trim();
  const targetGroupId = targetUserId ? `__USER__:${targetUserId}` : String(input.targetGroupId ?? '').trim();
  const requestId = String(input.requestId ?? '').trim();
  const scheduledAt = new Date(String(input.scheduledAt ?? ''));
  const ms = scheduledAt.getTime();
  const now = Date.now();
  if (!/^[A-Za-z0-9_-]{8,64}$/.test(requestId) ||
      !content || content.length > 3000 || !targetGroupId ||
      !Number.isFinite(ms) || ms < now + 60_000 ||
      ms > now + 30 * 24 * 60 * 60 * 1000) {
    throw new HttpsError('invalid-argument', 'Invalid scheduled message or date.');
  }
  if (!(await validateInternalDestination(uid, actor, targetGroupId, targetUserId, type))) {
    throw new HttpsError('permission-denied', 'Recipient is outside your role or municipality.');
  }
  const ref = db.collection('scheduled_messages').doc(`${uid}_${requestId}`);
  try {
    await ref.create({
      senderId: uid, targetGroupId,
      ...(targetUserId ? { targetUserId } : {}),
      content, type, status: 'scheduled',
      scheduledAt: Timestamp.fromDate(scheduledAt),
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  } catch (e: any) {
    if (e?.code !== 6 && e?.code !== 'already-exists') throw e;
    const current = (await ref.get()).data() ?? {};
    return { requestId, status: String(current.status ?? 'scheduled'), duplicate: true };
  }
  return { requestId, status: 'scheduled', duplicate: false };
});

export const cancelScheduledMessage = onCall({ region: 'us-central1' }, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in first.');
  await requireActor(request.auth.uid);
  const id = String((request.data as Record<string, unknown> | undefined)?.id ?? '');
  if (!id.startsWith(`${request.auth.uid}_`) || id.length > 256) {
    throw new HttpsError('permission-denied', 'Can cancel only your own queued message.');
  }
  const ref = db.collection('scheduled_messages').doc(id);
  await db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()?.senderId !== request.auth?.uid) {
      throw new HttpsError('not-found', 'Scheduled message not found.');
    }
    if (snap.data()?.status !== 'scheduled') {
      throw new HttpsError('failed-precondition', 'Message is no longer cancellable.');
    }
    tx.update(ref, { status: 'cancelled', updatedAt: FieldValue.serverTimestamp() });
  });
  return { cancelled: true };
});

export const dispatchScheduledMessages = onSchedule({
  schedule: 'every 5 minutes', timeZone: 'UTC', region: 'us-central1',
}, async () => {
  const due = await db.collection('scheduled_messages')
    .where('status', '==', 'scheduled')
    .where('scheduledAt', '<=', Timestamp.now())
    .limit(100).get();
  for (const document of due.docs) {
    try {
      // Validate scope immediately before sending, so role revocations
      // and group transfers prevent outdated instructions.
      const data = document.data();
      const actor = (await db.collection('users').doc(String(data.senderId)).get()).data();
      const allowed = actor && await validateInternalDestination(
        String(data.senderId), actor, String(data.targetGroupId),
        String(data.targetUserId ?? ''), String(data.type));
      if (!allowed) {
        await document.ref.update({
          status:'failed', reason:'permission-or-recipient-changed',
          updatedAt:FieldValue.serverTimestamp(),
        });
        continue;
      }
      const messageRef = db.collection('messages').doc(`scheduled_${document.id}`);
      await db.runTransaction(async tx => {
        const [schedule, existing] = await Promise.all([
          tx.get(document.ref), tx.get(messageRef),
        ]);
        if (schedule.data()?.status !== 'scheduled') return;
        if (!existing.exists) {
          tx.create(messageRef, {
            messageId: messageRef.id,
            senderId: data.senderId,
            targetGroupId: data.targetGroupId,
            ...(data.targetUserId ? { targetUserId: data.targetUserId } : {}),
            content: data.content, type: data.type,
            timestamp: FieldValue.serverTimestamp(), isRead: false,
          });
        }
        tx.update(document.ref, {
          status: 'sent', sentMessageId: messageRef.id,
          updatedAt: FieldValue.serverTimestamp(),
        });
      });
    } catch (error) {
      console.error('Scheduled message could not be processed', document.id,
        error instanceof Error ? error.message : 'Unknown error');
      // Remains scheduled for the next safe retry, without generating duplicate IDs.
    }
  }
});
