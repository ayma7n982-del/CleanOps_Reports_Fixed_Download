import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'data_service.dart';

/// A full, group-scoped live query avoids the global operations cache's limit.
/// Offline edits overlay the snapshot only while they remain in the durable queue.
class WorkReportSources extends ChangeNotifier {
  final DataService data;
  String groupId = '';
  List<Map<String, dynamic>>? _remote;
  bool _confirmed = false;
  String? error;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  WorkReportSources(this.data) {
    data.addListener(_changed);
  }
  void _changed() => notifyListeners();
  bool get serverConfirmed => _confirmed && data.online && error == null;

  static List<Map<String, dynamic>> overlay(
    DataService data,
    Iterable<Map<String, dynamic>> base,
    String groupId,
  ) {
    final result = <String, Map<String, dynamic>>{
      for (final row in base)
        if ('${row['groupId'] ?? ''}' == groupId &&
            '${row['id'] ?? ''}'.isNotEmpty)
          '${row['id']}': _normalize(row),
    };
    for (final item in data.queue) {
      if (!const {
        'attendance',
        'attendance_checkout',
        'trip',
        'worker',
        'work_report',
        'report',
      }.contains(item.entity))
        continue;
      try {
        final row = Map<String, dynamic>.from(jsonDecode(item.payload) as Map);
        final id = '${row['id'] ?? ''}';
        final previous = result[id];
        if (id.isEmpty) continue;
        if ('${row['groupId'] ?? previous?['groupId'] ?? ''}' != groupId) {
          if (previous != null)
            result[id] = {
              ...previous,
              'isDeleted': true,
              '_pendingSource': true,
            };
          continue;
        }
        result[id] = {
          ...?previous,
          ...row,
          '_entity': item.entity == 'attendance_checkout'
              ? 'attendance'
              : item.entity,
          if (item.operation == 'delete') 'isDeleted': true,
          '_pendingSource': true,
        };
      } catch (_) {
        /* Invalid queue data cannot replace a valid source. */
      }
    }
    return result.values.toList();
  }

  List<Map<String, dynamic>> get records => overlay(
    data,
    _confirmed ? (_remote ?? []) : [...data.operations, ...?_remote],
    groupId,
  );

  void bind(String value) {
    if (groupId == value) return;
    _subscription?.cancel();
    groupId = value;
    _remote = null;
    _confirmed = false;
    error = null;
    if (value.isEmpty || Firebase.apps.isEmpty) return;
    _subscription = FirebaseFirestore.instance
        .collection('operations')
        .where('groupId', isEqualTo: value)
        .snapshots(includeMetadataChanges: true)
        .listen(
          (snap) {
            if (groupId != value) return;
            _remote = snap.docs
                .map(
                  (doc) => <String, dynamic>{
                    ..._normalize(doc.data()),
                    'id': doc.id,
                  },
                )
                .toList();
            _confirmed =
                !snap.metadata.isFromCache && !snap.metadata.hasPendingWrites;
            error = null;
            notifyListeners();
          },
          onError: (Object e) {
            if (groupId != value) return;
            error = 'تعذر تأكيد اكتمال سجلات المجموعة؛ يمكنك حفظ مسودة محلية.';
            _confirmed = false;
            notifyListeners();
          },
        );
  }

  static Map<String, dynamic> _normalize(Map<String, dynamic> row) => {
    for (final e in row.entries)
      e.key: e.value is Timestamp
          ? (e.value as Timestamp).toDate().toIso8601String()
          : e.value,
  };

  /// Submission requires a fresh server read; failures must never turn into zero.
  static Future<List<Map<String, dynamic>>> readConfirmed(
    DataService data,
    String groupId,
  ) async {
    if (groupId.isEmpty || !data.online || Firebase.apps.isEmpty) {
      throw StateError(
        'يتطلب إرسال التقرير تأكيد سجلات المصدر بعد عودة الاتصال. المسودة محفوظة.',
      );
    }
    final snap = await FirebaseFirestore.instance
        .collection('operations')
        .where('groupId', isEqualTo: groupId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 20));
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites)
      throw StateError('انتظر تأكيد مزامنة سجلات المصدر ثم أعد الإرسال.');
    return overlay(
      data,
      snap.docs.map(
        (doc) => <String, dynamic>{..._normalize(doc.data()), 'id': doc.id},
      ),
      groupId,
    );
  }

  @override
  void dispose() {
    data.removeListener(_changed);
    _subscription?.cancel();
    super.dispose();
  }
}
