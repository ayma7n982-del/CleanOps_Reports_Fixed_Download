import { isDeepStrictEqual } from 'node:util';

// The owner can correct content and refresh counts before submission. Identity,
// scope and approval fields remain the saved values, even with a forged client.
export function validOwnerReportUpdate(
  current: Record<string, unknown>, incoming: Record<string, unknown>,
): boolean {
  const oldStatus = String(current.status ?? 'draft');
  const nextStatus = String(incoming.status ?? oldStatus);
  if (!['draft', 'needs_edits'].includes(oldStatus)
      || (nextStatus !== oldStatus && nextStatus !== 'submitted')) return false;
  const editable = new Set([
    'status', 'workTasks', 'completedWork', 'workLocations', 'containerStatus',
    'landfillStatus', 'problems', 'suggestions', 'contentEditedAt',
    'attendance', 'absence', 'specialLeave', 'sickLeave', 'otherAbsence', 'trips',
    'countsMode', 'sourceSnapshot', 'submittedAt', 'submittedBy',
  ]);
  // These values are normalized by saveOperationalReport, not accepted as-is.
  const normalized = new Set(['_entity', 'reportKind', 'updatedAt', 'updatedBy']);
  return Object.entries(incoming).every(([key, value]) =>
    editable.has(key) || normalized.has(key) || isDeepStrictEqual(value, current[key]));
}
