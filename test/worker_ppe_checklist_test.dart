import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/worker_ppe_checklist.dart';

void main() {
  test('checking all five chips allows validation and queues the same values', () {
    final checks = WorkerPpeChecklist();
    final chips = checks.forWorker('worker-1');
    expect(checks.isComplete('worker-1'), isFalse);
    for (final item in WorkerPpeChecklist.requiredItems) {
      chips[item] = true;
    }
    expect(checks.isComplete('worker-1'), isTrue);
    expect(checks.snapshot('worker-1'), chips);
  });

  test('quick approval and individual chips share the worker ID state', () {
    final checks = WorkerPpeChecklist();
    final chips = checks.forWorker('worker-1');
    checks.setAll('worker-1', true);
    expect(chips.values, everyElement(isTrue));
    expect(checks.isComplete('worker-1'), isTrue);
    chips['بوت'] = false;
    expect(checks.isComplete('worker-1'), isFalse);
    expect(checks.snapshot('worker-1')['بوت'], isFalse);
    checks.setAll('worker-1', false);
    expect(chips.values, everyElement(isFalse));
    expect(checks.isComplete('worker-1'), isFalse);
  });

  test('workers with identical names keep independent safety checks', () {
    final workers = [
      {'id': 'worker-1', 'name': 'محمد أحمد'},
      {'id': 'worker-2', 'name': 'محمد أحمد'},
    ];
    final checks = WorkerPpeChecklist();
    checks.setAll(workers.first['id']!, true);
    expect(checks.isComplete(workers.first['id']!), isTrue);
    expect(checks.isComplete(workers.last['id']!), isFalse);
    expect(checks.snapshot(workers.last['id']!).values, everyElement(isFalse));
    checks.setAll(workers.last['id']!, false);
    expect(checks.isComplete(workers.first['id']!), isTrue);
  });

  test('renaming a worker preserves safety selections for the same ID', () {
    final worker = {'id': 'worker-1', 'name': 'محمد'};
    final checks = WorkerPpeChecklist();
    checks.setAll(worker['id']!, true);
    worker['name'] = 'محمد أحمد';
    expect(checks.isComplete(worker['id']!), isTrue);
  });

  test('each required item must be checked before attendance is accepted', () {
    for (final missing in WorkerPpeChecklist.requiredItems) {
      final checks = WorkerPpeChecklist()..setAll('worker-1', true);
      checks.forWorker('worker-1')[missing] = false;
      expect(checks.isComplete('worker-1'), isFalse, reason: missing);
      checks.forWorker('worker-1').remove(missing);
      expect(checks.isComplete('worker-1'), isFalse, reason: missing);
    }
  });

  test('five unrelated true keys cannot pass the required equipment check', () {
    final checks = WorkerPpeChecklist();
    checks.forWorker('worker-1')
      ..clear()
      ..addAll({for (var i = 0; i < 5; i++) 'unknown-$i': true});
    expect(checks.isComplete('worker-1'), isFalse);
    expect(checks.snapshot('worker-1').values, everyElement(isFalse));
  });

  test('queued snapshots remain unchanged by subsequent draft edits', () {
    final checks = WorkerPpeChecklist()..setAll('worker-1', true);
    final queued = checks.snapshot('worker-1');
    checks.setAll('worker-1', false);
    expect(queued.values, everyElement(isTrue));
    expect(checks.snapshot('worker-1').values, everyElement(isFalse));
    queued['بوت'] = false;
    checks.setAll('worker-1', true);
    expect(queued['بوت'], isFalse);
  });

  test('unreviewed worker and new attendance sheet are never complete', () {
    final checks = WorkerPpeChecklist()..setAll('worker-1', true);
    expect(checks.isComplete('worker-2'), isFalse);
    expect(WorkerPpeChecklist().isComplete('worker-1'), isFalse);
  });

  test('missing worker IDs cannot share an anonymous safety check', () {
    final checks = WorkerPpeChecklist();
    expect(() => checks.forWorker(''), throwsArgumentError);
    expect(() => checks.setAll('   ', true), throwsArgumentError);
    expect(checks.isComplete(''), isFalse);
  });
}
