/// Draft PPE selections for one attendance sheet, keyed only by worker ID.
/// Worker names are display labels and must never identify a safety check.
class WorkerPpeChecklist {
  static const requiredItems = ['صديري', 'قفازات', 'بوت', 'كمامة', 'قبعة'];

  final Map<String, Map<String, bool>> _byWorkerId = {};

  Map<String, bool> forWorker(String workerId) {
    if (workerId.trim().isEmpty) {
      throw ArgumentError.value(workerId, 'workerId', 'A worker ID is required');
    }
    return _byWorkerId.putIfAbsent(
      workerId,
      () => {for (final item in requiredItems) item: false},
    );
  }

  void setAll(String workerId, bool approved) {
    final state = forWorker(workerId);
    for (final item in requiredItems) {
      state[item] = approved;
    }
  }

  bool isComplete(String workerId) => requiredItems.every(
    (item) => _byWorkerId[workerId]?[item] == true,
  );

  /// Detach the queued attendance payload from later edits to the UI draft.
  Map<String, bool> snapshot(String workerId) => {
    for (final item in requiredItems)
      item: _byWorkerId[workerId]?[item] == true,
  };
}
