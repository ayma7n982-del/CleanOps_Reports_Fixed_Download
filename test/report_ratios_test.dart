import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/report_ratios.dart';

void main() {
  test('growth, shares, achievement and variance handle zeros and invalid values', () {
    expect(RatioMath.growth(120, 100), 20);
    expect(RatioMath.growth(50, 100), -50);
    expect(RatioMath.growth(0, 10), -100);
    expect(RatioMath.growth(10, 0), isNull);
    expect(RatioMath.percent(0, 0), isNull);
    expect(RatioMath.percent(3, 2), isNull);
    expect(RatioMath.percent(3, 2, bounded: false), 150);
    expect(RatioMath.variance(3, 2), 50);
    expect(RatioMath.percent(double.nan, 2), isNull);
    expect(RatioMath.percent(1, double.infinity), isNull);
    expect(RatioMath.pointChange(90, 100, 80, 100), 10);
    expect(RatioMath.growth(90, 80), 12.5);
  });
  test('completion, response and growth use their own denominators', () {
    final ratios = ReportRatioEngine.build(current: [
      {'_entity': 'trip', 'status': 'completed'},
      {'_entity': 'trip', 'status': 'in_progress'},
      {'_entity': 'trip', 'status': 'cancelled'},
      {'_entity': 'emergency', 'acknowledged': true},
      {'_entity': 'emergency', 'acknowledged': false},
    ], previous: [{'_entity':'trip'}], previousLabel:'prior', comparisonComplete:true,
      reportType:'all', verifiedTarget: 2);
    ReportRatio get(String id) => ratios.firstWhere((r) => r.id == id);
    expect(get('growth').value, 200);
    expect(get('completion').value, closeTo(100 / 3, .0001));
    expect(get('response').value, 50);
    expect(get('achievement').value, 50);
    expect(get('variance').value, -50);
  });
  test('unknown statuses, incomplete comparisons and missing acknowledgement are not zero', () {
    final ratios = ReportRatioEngine.build(current: [
      {'_entity':'trip'}, {'_entity':'emergency'},
    ], previous: [{'_entity':'trip'}], previousLabel:'prior', comparisonComplete:false, reportType:'all');
    for (final id in ['growth', 'completion', 'response', 'achievement', 'variance']) {
      expect(ratios.firstWhere((r) => r.id == id).value, isNull, reason:id);
    }
  });
  test('composition uses full totals, not just the displayed top elements', () {
    final counts = [8, 4, 2, 2, 1, 1, 1, 1, 20];
    final total = counts.reduce((a, b) => a + b);
    expect(RatioMath.percent(counts.first, total), 20);
    expect(counts.map((n) => RatioMath.percent(n, total)!).reduce((a, b) => a + b), closeTo(100, .00001));
  });
}
