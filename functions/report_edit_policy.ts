import { gunzipSync } from 'node:zlib';
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

export function reviewFields(status: string, actor: string, time: string, reason?: unknown): Record<string, unknown> | null {
  if (status === 'approved') return { status, approvedBy: actor, approvedAt: time };
  if (status === 'closed') return { status, closedBy: actor, closedAt: time };
  const note = typeof reason === 'string' ? reason.trim() : '';
  if (status !== 'needs_edits' || !note || note.length > 1000) return null;
  return { status, returnReason: note, returnedAt: time };
}

export function aggregateCorrection(report: Record<string, unknown>): Record<string, unknown> | null {
  const note = typeof report.correctionNote === 'string' ? report.correctionNote.trim() : '';
  if (!note || note.length > 1000 || typeof report.archiveV1 !== 'string'
      || !report.archiveV1.length || report.archiveV1.length > 900000
      || !validReportArchive(report)) return null;
  return { status: 'submitted', correctionNote: note, partialSource: report.partialSource === true, snapshot: report.snapshot, archiveV1: report.archiveV1 };
}

// Verify that the numbers shown to the council match the immutable export payload.
export function validReportArchive(report: Record<string, unknown>): boolean {
  const archive = report.archiveV1;
  const summary = report.snapshot;
  if (typeof archive !== 'string' || !archive.length || archive.length > 900000 ||
      !summary || typeof summary !== 'object' || Array.isArray(summary)) return false;
  try {
    const saved = JSON.parse(gunzipSync(Buffer.from(archive, 'base64'), {maxOutputLength: 32 * 1024 * 1024}).toString());
    const counts = summary as Record<string, unknown>;
    return typeof saved.generatedAt === 'string' && Number.isFinite(Date.parse(saved.generatedAt)) &&
      ['trips','completedTrips','attendance','absence','workers','supervisors','groups','containers','emergencies'].every(key =>
        Number.isSafeInteger(counts[key]) && Number(counts[key]) >= 0 &&
        saved[key === 'containers' ? 'containersTotal' : key] === counts[key]);
  } catch { return false; }
}
