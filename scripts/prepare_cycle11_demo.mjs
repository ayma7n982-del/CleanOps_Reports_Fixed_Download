import {cert, deleteApp, initializeApp} from 'firebase-admin/app';
import {FieldValue, getFirestore} from 'firebase-admin/firestore';
import assert from 'node:assert/strict';

const projectId = 'nrc-aid';
const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT ?? '{}');
assert.equal(serviceAccount.project_id, projectId, 'Unexpected service account project');
const app = initializeApp({projectId, credential: cert(serviceAccount)});
const db = getFirestore(app);
const cycleId = 'sim_cycle_11_oct_2026';
const name = 'الدورة 11 التجريبية - أكتوبر 2026';
const municipalityName = 'بلدية بني سهيلا';
const simulation = {isSimulation: true, simulationName: name};
const shift = 'صباحي';
const date = (day, time = '08:00:00') =>
  `2026-10-${String(day).padStart(2, '0')}T${time}+03:00`;
const isDemo = (snapshot) => snapshot.data()?.isSimulation === true;
const cycleRef = db.collection('work_cycles').doc(cycleId);
const operations = db.collection('operations');
const users = db.collection('users');

try {
  const [cycle, previous, coordinators] = await Promise.all([
    cycleRef.get(), operations.where('cycleId', '==', cycleId).get(),
    users.where('role', '==', 'municipality_coordinator').get(),
  ]);
  if (cycle.exists) assert.ok(isDemo(cycle), 'Cycle ID belongs to a non-demo record');
  const matches = coordinators.docs.filter((doc) => {
    const user = doc.data();
    return user.isActive !== false &&
      /بني\s+سهيلا/.test(String(user.municipalityName ?? user.scope ?? ''));
  });
  const existingGroups = previous.docs.filter((doc) => doc.data()._entity === 'group' && isDemo(doc));
  const priorOwner = existingGroups.map((doc) => doc.data().municipalityCoordinatorId)
      .find((id) => matches.some((doc) => doc.id === id));
  const owner = priorOwner ?? (matches.length === 1 ? matches[0].id : 'simulation');
  const coordinator = matches.find((doc) => doc.id === owner)?.data() ?? {};
  const scope = {...simulation, cycleId, cycleName: name, municipalityName,
    municipalityId: owner === 'simulation' ? 'sim_municipality_bani_suheila' : owner,
    municipalityCoordinatorId: owner, councilName: coordinator.councilName ?? ''};
  const roster = await users.where('cycleId', '==', cycleId).get();
  const writes = new Map();
  function add(ref, values) { writes.set(ref.path, [ref, values]); }

  for (let n = 1; n <= 5; n++) {
    const groupId = `sim_cycle11_group_${String(n).padStart(2, '0')}`;
    const groupName = `المجموعة التجريبية ${n}`;
    const group = {...scope, groupId, groupName};
    add(operations.doc(groupId), {...group, id: groupId, _entity: 'group', name: groupName,
      number: groupId, groupNumber: groupId, status: 'active', isActive: true, isDeleted: false,
      createdAt: date(1), updatedAt: date(20)});
    const supervisorId = `sim_cycle11_group${n}_supervisor`;
    const workerIds = [supervisorId,
      ...Array.from({length: 7}, (_, i) => `sim_cycle11_group${n}_collector${String(i + 1).padStart(2, '0')}`),
      ...[1, 2].map((i) => `sim_cycle11_group${n}_animalcart${i}`)];
    const profiles = workerIds.map((uid, i) => {
      const old = roster.docs.find((doc) => doc.id === uid)?.data();
      const role = i === 0 ? 'group_supervisor' : 'worker';
      return {...group, id: uid, userId: uid, username: uid, role, scope: municipalityName,
        name: old?.name ?? (i === 0 ? `مشرف تجريبي ${n}` : `عامل تجريبي ${n}-${i}`),
        isActive: true, isDeleted: false, status: 'active', createdAt: date(1), updatedAt: date(20)};
    });
    for (const profile of profiles) {
      add(users.doc(profile.id), profile);
      add(operations.doc(profile.id), {...profile, _entity: 'worker', workerId: profile.id,
        workerRole: profile.role, workerName: profile.name});
    }

    for (let day = 1; day <= 20; day++) {
      const stamp = date(day);
      const key = `${n}_${String(day).padStart(2, '0')}`;
      const counts = {attendance: 0, absence: 0, specialLeave: 0, sickLeave: 0, otherAbsence: 0};
      const attendanceIds = [];
      for (const [i, worker] of profiles.entries()) {
        const status = i === 0 || (i + day + n) % 13 > 2 ? 'present'
          : (i + day + n) % 13 === 0 ? 'absent' : 'leave';
        counts[status === 'present' ? 'attendance' : status === 'absent' ? 'absence' : 'specialLeave']++;
        const id = `sim_cycle11_att_${key}_${i}`;
        attendanceIds.push(id);
        add(operations.doc(id), {...group, id, _entity: 'attendance', shift, status,
          workerId: worker.id, workerName: worker.name, workerRole: worker.role,
          reportedBy: supervisorId, date: stamp, workDate: stamp, createdAt: stamp, updatedAt: stamp,
          ...(status === 'present' ? {checkInAt: stamp, checkOutAt: date(day, '15:00:00'),
            ppeComplete: (i + day) % 7 !== 0} : {})});
      }
      const existingTrips = previous.docs.filter((doc) => {
        const item = doc.data();
        return isDemo(doc) && item._entity === 'trip' && item.groupId === groupId &&
          Date.parse(item.createdAt ?? item.date) >= Date.parse(date(day, '00:00:00')) &&
          Date.parse(item.createdAt ?? item.date) <= Date.parse(date(day, '23:59:59')) &&
          ['completed', 'delivered'].includes(item.status);
      });
      const tripIds = existingTrips.map((doc) => doc.id);
      if (tripIds.length === 0) {
        for (let t = 0; t < 2 + ((day + n) % 3); t++) {
          const id = `sim_cycle11_demo_trip_${key}_${t}`;
          tripIds.push(id);
          add(operations.doc(id), {...group, id, _entity: 'trip', shift, status: 'completed',
            reportedBy: supervisorId, supervisorId, date: stamp, workDate: stamp,
            createdAt: stamp, startedAt: stamp, completedAt: date(day, '11:00:00'),
            weightTons: 1.4 + t * 0.35, sourceLocation: `المسار التجريبي ${n}`,
            destinationDumpsiteName: 'مكب تجريبي', notes: 'بيانات اختبار للدورة 11'});
        }
      }
      const id = `sim_cycle11_work_${key}`;
      add(operations.doc(id), {...group, id, _entity: 'work_report', reportKind: 'work_report',
        recordType: 'daily_work', status: 'draft', shift, reportedBy: supervisorId,
        reporterName: profiles[0].name, workDate: stamp, createdAt: stamp, updatedAt: stamp,
        ...counts, trips: tripIds.length, countsMode: 'operational_sources_v1',
        sourceSnapshot: {serverConfirmed: true, needsReview: false, activeTrips: 0,
          cancelledTrips: 0, attendanceIds, tripIds, groupId, shift},
        workTasks: 'جمع النفايات وتنظيف نقاط التجميع', workLocations: `المسار التجريبي ${n}`,
        completedWork: `أُنجزت ${tripIds.length} نقلات في يوم العمل التجريبي ${day}`,
        problems: day % 5 === 0 ? 'تأخر تجريبي في إحدى نقاط الجمع' : 'لا عوائق مسجلة',
        suggestions: 'متابعة حالة الحاويات في الجولة التالية', isDeleted: false});
    }
  }

  const entries = [...writes.values()];
  // Validate every planned ID before creating or changing any Firestore record.
  for (let start = 0; start < entries.length; start += 250) {
    const existing = await db.getAll(...entries.slice(start, start + 250).map(([ref]) => ref));
    for (const doc of existing) if (doc.exists) {
      assert.ok(isDemo(doc) && doc.data().cycleId === cycleId, `Refusing to modify ${doc.ref.path}`);
    }
  }
  for (let start = 0; start < entries.length; start += 250) {
    const batch = db.batch();
    for (const [ref, values] of entries.slice(start, start + 250)) batch.set(ref, values, {merge: true});
    await batch.commit();
  }
  await cycleRef.set({...simulation, id: cycleId, name, cycleNumber: 11,
    municipalityName, status: 'active', isActive: true, isDeleted: false, startDate: new Date(date(1, '00:00:00')),
    endDate: new Date(date(20, '23:59:59')), updatedAt: FieldValue.serverTimestamp()}, {merge: true});

  const verified = await operations.where('cycleId', '==', cycleId).get();
  const demo = verified.docs.map((doc) => doc.data()).filter((doc) => doc.isSimulation === true);
  const attend = demo.filter((doc) => doc._entity === 'attendance' && doc.id?.startsWith('sim_cycle11_att_'));
  const works = demo.filter((doc) => doc._entity === 'work_report' && doc.id?.startsWith('sim_cycle11_work_'));
  const groups = new Set(works.map((doc) => doc.groupId));
  assert.equal(groups.size, 5);
  assert.equal(attend.length, 1000);
  assert.equal(works.length, 100);
  for (const group of groups) assert.equal(new Set(
    works.filter((doc) => doc.groupId === group).map((doc) => doc.workDate)).size, 20);
  console.log(JSON.stringify({cycle: cycleId, groups: 5, days: 20, attendance: attend.length,
    workReports: works.length, tripRecords: demo.filter((doc) => doc._entity === 'trip').length,
    linkedToMunicipalCoordinator: owner !== 'simulation'}));
} finally {
  await deleteApp(app);
}
