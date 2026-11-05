import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'data_service.dart';
import 'work_report_summary.dart';

class DailyWorkReportPhoto {
  final Uint8List bytes;
  final String caption;
  const DailyWorkReportPhoto(this.bytes, this.caption);
}

class _RankedPhoto {
  final DailyWorkReportPhoto photo;
  final double score;
  const _RankedPhoto(this.photo, this.score);
}

/// Uses only photos attached to verified trips in this group, day and shift.
/// Failed downloads are skipped; the report never substitutes stock imagery.
class DailyWorkReportPhotoSelector {
  const DailyWorkReportPhotoSelector._();

  static Future<DailyWorkReportPhoto?> select(
    Map<String, dynamic> report,
    DataService data,
  ) async {
    final group = '${report['groupId'] ?? ''}'.trim();
    final day = WorkReportSummary.date(report['workDate']);
    final shift = '${report['shift'] ?? ''}'.trim();
    if (group.isEmpty || day == null || shift.isEmpty) return null;

    var rows = data.operations;
    if (data.online && Firebase.apps.isNotEmpty) {
      try {
        final snap = await FirebaseFirestore.instance.collection('operations')
            .where('groupId', isEqualTo: group)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));
        rows = snap.docs.map((doc) => <String, dynamic>{
          ...doc.data(), 'id': doc.id,
        }).toList();
      } catch (_) {
        // A cached report can still be exported without a field photograph.
      }
    }
    final captured = report['sourceSnapshot'];
    final savedIds = captured is Map && captured['tripIds'] is List
        ? (captured['tripIds'] as List).map((v) => '$v').toSet()
        : <String>{};
    final trips = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      if (row['_entity'] != 'trip' || row['isDeleted'] == true ||
          '${row['groupId'] ?? ''}' != group || '${row['shift'] ?? ''}' != shift ||
          (row['photoCount'] is! num || (row['photoCount'] as num) <= 0)) continue;
      final at = WorkReportSummary.date(
          row['workDate'] ?? row['startedAt'] ?? row['createdAt']);
      if (at == null || WorkReportSummary.dayKey(at) != WorkReportSummary.dayKey(day)) continue;
      final id = '${row['id'] ?? ''}';
      if (id.isNotEmpty && (savedIds.isEmpty || savedIds.contains(id))) trips[id] = row;
    }
    if (trips.isEmpty || Firebase.apps.isEmpty || !data.online) return null;

    final ids = trips.keys.toList()..sort();
    final photos = <Map<String, dynamic>>[];
    // Firestore limits the number of values in a whereIn query.
    for (var offset = 0; offset < ids.length; offset += 30) {
      final chunk = ids.skip(offset).take(30).toList();
      try {
        final snap = await FirebaseFirestore.instance.collection('operations')
            .where('parentTripId', whereIn: chunk)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 20));
        for (final doc in snap.docs) {
          final photo = doc.data();
          final trip = trips['${photo['parentTripId'] ?? ''}'];
          if (photo['_entity'] != 'trip_photo' || photo['isDeleted'] == true ||
              trip == null || '${photo['userId'] ?? ''}' != '${trip['supervisorId'] ?? ''}' ||
              '${photo['attachmentUrl'] ?? ''}'.isEmpty) continue;
          photos.add({...photo, 'id': doc.id});
        }
      } catch (_) {
        // Some older records may not have accessible uploaded photos.
      }
    }
    // Limit decoding and bandwidth; select from the latest verified field photos.
    photos.sort((a, b) => '${b['createdAt'] ?? ''}'.compareTo('${a['createdAt'] ?? ''}'));
    Future<_RankedPhoto?> evaluate(Map<String, dynamic> photo) async {
      try {
        final bytes = await FirebaseStorage.instance
            .refFromURL('${photo['attachmentUrl']}')
            .getData(2 * 1024 * 1024)
            .timeout(const Duration(seconds: 7));
        if (bytes == null || bytes.isEmpty) return null;
        final score = await _quality(bytes);
        final trip = trips['${photo['parentTripId']}']!;
        final street = '${trip['street'] ?? ''}'.trim();
        return _RankedPhoto(DailyWorkReportPhoto(bytes,
            street.isEmpty ? 'صورة موثقة من نقلة المجموعة' : 'صورة ميدانية - $street'), score);
      } catch (_) {
        return null;
      }
    }
    _RankedPhoto? best;
    final shortlist = photos.take(18).toList();
    for (var offset = 0; offset < shortlist.length; offset += 6) {
      final ranked = await Future.wait(shortlist.skip(offset).take(6).map(evaluate));
      for (final candidate in ranked.whereType<_RankedPhoto>()) {
        if (best == null || candidate.score > best.score) best = candidate;
      }
    }
    return best?.photo;
  }

  static Future<double> _quality(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 160);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return double.negativeInfinity;
      final width = image.width, height = image.height;
      var brightness = 0.0, edges = 0.0, count = 0;
      for (var y = 2; y < height; y += 2) {
        for (var x = 2; x < width; x += 2) {
          final at = 4 * (y * width + x);
          final left = at - 8, above = at - 8 * width;
          final value = (pixels.getUint8(at) * 3 +
              pixels.getUint8(at + 1) * 6 + pixels.getUint8(at + 2)) / 10;
          final leftValue = (pixels.getUint8(left) * 3 +
              pixels.getUint8(left + 1) * 6 + pixels.getUint8(left + 2)) / 10;
          final aboveValue = (pixels.getUint8(above) * 3 +
              pixels.getUint8(above + 1) * 6 + pixels.getUint8(above + 2)) / 10;
          brightness += value;
          edges += (value - leftValue).abs() + (value - aboveValue).abs();
          count++;
        }
      }
      if (count == 0) return double.negativeInfinity;
      // Favor visible detail and a balanced exposure; no object recognition or
      // claim that this heuristic measures the quality of the work itself.
      return edges / count - (brightness / count - 128).abs() * .2;
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}
