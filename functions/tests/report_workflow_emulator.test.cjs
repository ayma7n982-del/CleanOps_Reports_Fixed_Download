const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');

test('the stored report survives return, correction, concurrent reviews, replay and closure', {
  skip: !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || ''),
}, async () => {
  process.env.GCLOUD_PROJECT = 'demo-cleanops-report-workflow';
  const { saveOperationalReport } = require('../lib/index');
  const { getFirestore } = require('firebase-admin/firestore');
  const db = getFirestore();
  const id = randomUUID();
  const ref = db.collection('operations').doc(id);
  for (const [uid, role, scope] of [
    ['mun','municipality_coordinator','town'], ['other','municipality_coordinator','other'],
    ['council','jsc_coordinator','north'], ['foreign','jsc_coordinator','south'], ['manager','donor_manager','all'],
  ]) await db.collection('users').doc(uid).set({role,scope,isActive:true});
  const call = (uid, operation, report, expectedRevision, requestId = randomUUID()) =>
    saveOperationalReport.run({auth:{uid},data:{operation,sourceEntity:'report_approval',report:{id,...report},expectedRevision,requestId}});

  const archive = trips => {
    const snapshot = {trips,completedTrips:trips,attendance:0,absence:0,workers:0,supervisors:0,
      groups:0,containers:0,emergencies:0};
    const saved = {...snapshot,containersTotal:0,generatedAt:'2026-11-01T08:00:00Z'};
    return {snapshot,archiveV1:require('node:zlib').gzipSync(JSON.stringify(saved)).toString('base64')};
  };
  const submit = {status:'submitted',requestedBy:'mun',municipalityCoordinatorId:'mun',
    municipalityName:'town',councilName:'north',...archive(3)};
  await assert.rejects(call('mun','create',{...submit,snapshot:{...submit.snapshot,trips:43}}), {code:'invalid-argument'});
  const createId = randomUUID();
  await call('mun','create',submit,undefined,createId);
  await call('mun','create',submit,undefined,createId);
  await assert.rejects(call('foreign','update',{status:'approved'},1), {code:'permission-denied'});
  await assert.rejects(call('council','update',{status:'needs_edits',returnReason:' '},1), {code:'invalid-argument'});
  await call('council','update',{status:'needs_edits',returnReason:'راجع النقلات'},1);
  const correction = {status:'submitted',...archive(4),correctionNote:'اكتملت نقلة أخرى'};
  await assert.rejects(call('other','update',correction,2), {code:'permission-denied'});
  await call('mun','update',correction,2);
  await assert.rejects(call('council','update',{status:'approved'},1),{code:'failed-precondition'});
  const approvalId = randomUUID();
  const accept = () => call('council','update',{status:'approved',archiveV1:'replacement',snapshot:{trips:999}},3,approvalId);
  await Promise.all([accept(), accept()]);
  await call('manager','update',{status:'closed'},4);
  await accept();
  const final = (await ref.get()).data();
  assert.equal(final.status,'closed');
  assert.equal(final.revision,5);
  assert.deepEqual(final.snapshot,archive(4).snapshot);
  assert.equal(final.archiveV1,correction.archiveV1);
  assert.equal(final.returnReason,'راجع النقلات');
  assert.equal(final.approvedBy,'council');
  const audit = await db.collection('audit').where('targetId','==',id).get();
  assert.equal(audit.size,5);
  await db.terminate();
});
