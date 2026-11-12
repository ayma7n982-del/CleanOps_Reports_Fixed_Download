const { test } = require('node:test');
const assert = require('node:assert/strict');
const { validOwnerReportUpdate } = require('../lib/report_edit_policy');
const saved = { id: 'r1', reportedBy: 's1', groupId: 'g1', municipalityName: 'm1',
  cycleId: 'c1', workDate: '2026-11-12', status: 'needs_edits', workTasks: 'old' };
test('returned report can be corrected and resubmitted with refreshed source counts', () => {
  assert.equal(validOwnerReportUpdate(saved, { ...saved, workTasks: 'corrected' }), true);
  assert.equal(validOwnerReportUpdate(saved, { ...saved, status: 'submitted',
    attendance: 19, sourceSnapshot: { fingerprint: 'new' }, submittedBy: 's1' }), true);
});
test('identity and approval changes are rejected even alongside valid corrections', () => {
  for (const key of ['id', 'reportedBy', 'groupId', 'municipalityName', 'cycleId',
    'workDate', 'approvedBy', 'approvedAt', 'createdBy']) {
    assert.equal(validOwnerReportUpdate(saved, { ...saved, [key]: 'forged' }), false, key);
  }
});
test('approved reports and direct approval transitions cannot be edited by owner', () => {
  assert.equal(validOwnerReportUpdate({ ...saved, status: 'approved' }, { workTasks: 'changed' }), false);
  assert.equal(validOwnerReportUpdate(saved, { status: 'approved' }), false);
});
test('draft save is supported without changing identity', () => {
  assert.equal(validOwnerReportUpdate({ ...saved, status: 'draft' }, { status: 'draft', problems: 'road closed' }), true);
});
