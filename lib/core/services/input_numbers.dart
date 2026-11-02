/// Parse user input without turning missing or malformed values into zero.
class InputNumbers {
  static String normalize(String text) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    var result = text.trim();
    for (var i = 0; i < 10; i++) {
      result = result.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    // A single comma is a decimal separator. Grouping and mixed separators
    // are deliberately rejected rather than guessing a different quantity.
    return result.replaceAll('٫', '.').replaceAll(',', '.');
  }

  static int? whole(String text) {
    final value = normalize(text);
    if (!RegExp(r'^\d+$').hasMatch(value)) return null;
    return int.tryParse(value);
  }

  static double? decimal(String text) {
    final value = normalize(text);
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) return null;
    final number = double.tryParse(value);
    return number != null && number.isFinite ? number : null;
  }

  static String? wholeError(String? text) => whole(text ?? '') == null
      ? 'أدخل عددًا صحيحًا غير سالب، مثل 0 أو 12.'
      : null;

  static String? decimalError(
    String? text, {
    double? max,
    bool positive = false,
  }) {
    final value = decimal(text ?? '');
    if (value == null) return 'أدخل رقمًا صالحًا غير سالب، مثل 0 أو 12.5.';
    if (positive && value <= 0) return 'أدخل كمية أكبر من صفر.';
    if (max != null && value > max)
      return 'أدخل رقمًا بين 0 و${max.toStringAsFixed(0)}.';
    return null;
  }
}
