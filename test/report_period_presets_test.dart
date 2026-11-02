import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/report_service.dart';

void main() {
  test('daily preset is exactly one calendar day', () {
    final range = ReportPeriodPresets.daily(DateTime(2026, 10, 28, 18, 45));
    expect(range.startDate, DateTime(2026, 10, 28));
    expect(range.endDate, DateTime(2026, 10, 28));
    expect(range.inclusiveDays, 1);
  });

  test('weekly preset includes today and the previous six days', () {
    final range = ReportPeriodPresets.weekly(DateTime(2026, 10, 28, 18, 45));
    expect(range.startDate, DateTime(2026, 10, 22));
    expect(range.endDate, DateTime(2026, 10, 28));
    expect(range.inclusiveDays, 7);
  });

  test('custom period supports ranges longer than sixty days', () {
    final range = ReportPeriodPresets.custom(
      DateTime(2026, 8, 1, 20),
      DateTime(2026, 10, 28, 5),
    );
    expect(range.startDate, DateTime(2026, 8, 1));
    expect(range.endDate, DateTime(2026, 10, 28));
    expect(range.inclusiveDays, greaterThan(60));
  });

  test('custom period normalizes reversed dates', () {
    final range = ReportPeriodPresets.custom(
      DateTime(2026, 10, 28),
      DateTime(2026, 10, 20),
    );
    expect(range.startDate, DateTime(2026, 10, 20));
    expect(range.endDate, DateTime(2026, 10, 28));
    expect(range.inclusiveDays, 9);
  });
  test('calendar day counts survive spring and autumn clock changes', () {
    for (final period in [
      ReportPeriodPresets.custom(DateTime(2026, 3, 25), DateTime(2026, 3, 31)),
      ReportPeriodPresets.custom(DateTime(2026, 10, 22), DateTime(2026, 10, 28)),
    ]) {
      expect(period.inclusiveDays, 7);
    }
    final springWeek = ReportPeriodPresets.weekly(DateTime(2026, 3, 31));
    expect(springWeek.startDate, DateTime(2026, 3, 25));
    expect(springWeek.inclusiveDays, 7);
  });

}
