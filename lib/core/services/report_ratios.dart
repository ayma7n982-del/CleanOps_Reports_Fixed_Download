import 'trip_lifecycle.dart';

class RatioMath {
  static double? percent(num? numerator, num? denominator, {bool bounded = true}) {
    if (numerator == null || denominator == null || !numerator.isFinite ||
        !denominator.isFinite || numerator < 0 || denominator <= 0 ||
        bounded && numerator > denominator) return null;
    final result = numerator / denominator * 100;
    return result.isFinite ? result : null;
  }
  static double? growth(num? current, num? previous) {
    if (current == null || previous == null || !current.isFinite ||
        !previous.isFinite || current < 0 || previous <= 0) return null;
    final result = (current - previous) / previous * 100;
    return result.isFinite ? result : null;
  }
  static double? variance(num? actual, num? target) => growth(actual, target);
  static double? pointChange(num? nowNumerator, num? nowTotal, num? priorNumerator, num? priorTotal) {
    final now = percent(nowNumerator, nowTotal), prior = percent(priorNumerator, priorTotal);
    return now == null || prior == null ? null : now - prior;
  }
  static String display(double? value, {bool signed = false, bool points = false, bool english = false}) => value == null
      ? '—' : '${signed && value > 0 ? '+' : ''}${value.toStringAsFixed(1)}${points ? (english ? ' pp' : ' نقطة مئوية') : '%'}';
}

class ReportRatio {
  final String id, ar, en, basisAr, basisEn;
  final double? value;
  final bool signed, points;
  const ReportRatio(this.id, this.ar, this.en, this.value, this.basisAr, this.basisEn,
      {this.signed = false, this.points = false});
  String label(bool english) => english ? en : ar;
  String basis(bool english) => english ? basisEn : basisAr;
  String display(bool english) => RatioMath.display(value, signed: signed, points: points, english: english);
}

/// Derived only from already scoped and filtered source records. No writes.
class ReportRatioEngine {
  static List<ReportRatio> build({required List<Map<String, dynamic>> current,
    required List<Map<String, dynamic>> previous, required String previousLabel,
    required bool comparisonComplete, String? reportType, num? verifiedTarget}) {
    String entity(Map<String, dynamic> r) => '${r['_entity'] == 'report' ? r['reportKind'] : r['_entity']}';
    List<Map<String, dynamic>> trips(List<Map<String, dynamic>> rows) => rows.where((r) => ['trip', 'trips'].contains(entity(r))).toList();
    final work = reportType == 'work';
    final currentTrips = trips(current);
    double tripTotal(List<Map<String, dynamic>> rows) => work
        ? rows.where((r) => entity(r) == 'work_report').fold<double>(0, (sum, r) => sum + (r['trips'] is num ? (r['trips'] as num).toDouble() : 0))
        : trips(rows).length.toDouble();
    final nowCount = tripTotal(current), priorCount = tripTotal(previous);
    final ratios = <ReportRatio>[];
    if (reportType != 'containers' && reportType != 'absence') {
      final missingCounts = work && [...current, ...previous].where((r) => entity(r) == 'work_report').any((r) => r['trips'] is! num ||
        r['sourceSnapshot'] is! Map || (r['sourceSnapshot'] as Map)['serverConfirmed'] != true || (r['sourceSnapshot'] as Map)['needsReview'] == true);
      final growth = comparisonComplete && !missingCounts ? RatioMath.growth(nowCount, priorCount) : null;
      ratios.add(ReportRatio('growth', 'تغيّر النقلات عن الفترة السابقة', 'Trip growth vs previous period', growth,
        growth == null ? 'غير متاح: قاعدة سابقة غير موجبة أو بيانات المقارنة غير مكتملة.' : 'الحالي $nowCount؛ السابق $priorCount. الفترة السابقة: $previousLabel. اليوم الجاري قد يكون جزئيًا.',
        growth == null ? 'Unavailable: no positive baseline or incomplete comparison data.' : 'Current $nowCount; previous $priorCount. Previous period: $previousLabel. The current day may be partial.', signed: true));
      final complete = currentTrips.where((r) => TripLifecycle.isCompleted(r['status'])).length;
      final known = currentTrips.every((r) => TripLifecycle.isCompleted(r['status']) || const ['cancelled', 'canceled', 'rejected'].contains('${r['status']}') || TripLifecycle.activeStatuses.contains('${r['status']}'));
      ratios.add(ReportRatio('completion', 'إتمام النقلات المسجلة', 'Recorded trip completion',
        !work && known ? RatioMath.percent(complete, currentTrips.length) : null,
        !work && known && currentTrips.isNotEmpty ? '$complete مكتملة ÷ ${currentTrips.length} نقلة مسجلة، بما فيها الجارية والملغاة.' : 'غير متاح: لا توجد نقلات مباشرة مكتملة الحالة في مصدر هذا التقرير.',
        !work && known && currentTrips.isNotEmpty ? '$complete completed / ${currentTrips.length} recorded trips, including active and cancelled.' : 'Unavailable: no direct trips with fully known statuses in this report source.'));
      final workReports = current.where((r) => entity(r) == 'work_report').toList();
      final actual = work ? (!missingCounts && workReports.isNotEmpty ? nowCount : null)
          : known && currentTrips.isNotEmpty ? complete : null;
      final achieved = RatioMath.percent(actual, verifiedTarget, bounded: false);
      final variance = RatioMath.variance(actual, verifiedTarget);
      ratios.add(ReportRatio('achievement', 'الإنجاز مقابل الخطة', 'Achievement against plan', achieved,
        achieved == null ? 'غير متاح: يلزم مستهدف موثوق للفترة وأعداد تنفيذ مكتملة المصدر.'
            : '$actual نقلة مكتملة ÷ $verifiedTarget مستهدف يومي × 100. قد يتجاوز الإنجاز 100%، واليوم الجاري جزئي.',
        achieved == null ? 'Unavailable: a verified period target and complete actuals are required.'
            : '$actual completed trips / $verifiedTarget daily target × 100. Achievement may exceed 100%; the current day is partial.'));
      ratios.add(ReportRatio('variance', 'الانحراف عن المستهدف', 'Variance against target', variance,
        variance == null ? 'غير متاح: يلزم مستهدف موثوق للفترة وأعداد تنفيذ مكتملة المصدر.'
            : '($actual فعلي − $verifiedTarget مستهدف يومي) ÷ $verifiedTarget × 100.',
        variance == null ? 'Unavailable: a verified period target and complete actuals are required.'
            : '($actual actual − $verifiedTarget daily target) / $verifiedTarget × 100.', signed: true));
    }
    List<int> attendance(List<Map<String, dynamic>> rows) {
      final records = rows.where((r) => entity(r) == 'attendance');
      return [records.where((r) => ['present', 'حضور'].contains(r['status'])).length,
        records.where((r) => ['present', 'حضور', 'absent', 'غياب', 'excused_absence', 'unexcused_absence'].contains(r['status'])).length];
    }
    if (reportType != 'containers' && reportType != 'trips' && !work) {
      final now = attendance(current), prior = attendance(previous);
      final change = comparisonComplete ? RatioMath.pointChange(now[0], now[1], prior[0], prior[1]) : null;
      ratios.add(ReportRatio('attendanceChange', 'تغيّر الحضور بالنقاط المئوية', 'Attendance percentage-point change', change,
        change == null ? 'غير متاح: يلزم كشف حضور وغياب للفترتين.' : 'فرق نسبتي الحضور، وليس معدل النمو النسبي. السابقة: $previousLabel.',
        change == null ? 'Unavailable: attendance and absence records are needed for both periods.' : 'Difference between attendance percentages, not relative growth. Previous: $previousLabel.', signed: true, points: true));
    }
    if (reportType == null || ['all', 'executive'].contains(reportType)) {
      final incidents = current.where((r) => entity(r) == 'emergency').toList();
      final acknowledged = incidents.where((r) => r['acknowledged'] == true).length;
      final known = incidents.every((r) => r['acknowledged'] is bool);
      ratios.add(ReportRatio('response', 'تأكيد استلام بلاغات الطوارئ', 'Emergency acknowledgement rate',
        known ? RatioMath.percent(acknowledged, incidents.length) : null,
        known && incidents.isNotEmpty ? '$acknowledged مؤكدة الاستلام ÷ ${incidents.length} بلاغًا. لا تعني هذه النسبة إغلاق البلاغات.' : 'غير متاح: سجلات تأكيد الاستلام ناقصة أو لا توجد بلاغات.',
        known && incidents.isNotEmpty ? '$acknowledged acknowledged / ${incidents.length} incidents. This does not measure closure.' : 'Unavailable: missing acknowledgement data or no incidents.'));
    }
    return ratios;
  }
}
