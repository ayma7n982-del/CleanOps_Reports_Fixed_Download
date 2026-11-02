import 'package:flutter_test/flutter_test.dart';
import 'package:solid_waste_operations/core/services/input_numbers.dart';

void main() {
  test(
    'counts accept western, Arabic and Persian digits and explicit zero',
    () {
      expect(InputNumbers.whole(' ١٢ '), 12);
      expect(InputNumbers.whole('۱۲'), 12);
      expect(InputNumbers.whole('0'), 0);
      for (final text in [
        '',
        'abc',
        '-1',
        '1.5',
        'NaN',
        'Infinity',
        '1e3',
        '1 2',
      ]) {
        expect(InputNumbers.whole(text), isNull, reason: text);
        expect(InputNumbers.wholeError(text), isNotNull, reason: text);
      }
    },
  );
  test(
    'quantities support decimal separators without accepting nonfinite values',
    () {
      for (final text in ['١٢٫٥', '۱۲.۵', '12,5', '12.5']) {
        expect(InputNumbers.decimal(text), 12.5, reason: text);
      }
      for (final text in [
        '',
        'bad',
        '-2',
        'NaN',
        'Infinity',
        '1e999',
        '1,2.5',
        '1,000,000',
      ]) {
        expect(InputNumbers.decimal(text), isNull, reason: text);
      }
      expect(InputNumbers.decimalError('101', max: 100), isNotNull);
      expect(InputNumbers.decimalError('100', max: 100), isNull);
      expect(InputNumbers.decimalError('0', positive: true), isNotNull);
    },
  );
}
