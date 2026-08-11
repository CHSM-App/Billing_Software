/// Converts a rupee amount to words using the Indian numbering system
/// (Thousand / Lakh / Crore), for printed tax invoices — e.g.
///   24072   → "Twenty Four Thousand Seventy Two Rupees only"
///   100000  → "One Lakh Rupees only"
///   1234.50 → "One Thousand Two Hundred Thirty Four Rupees and Fifty Paise only"
///
/// Whole rupees are rounded from paise; a non-zero paise remainder is appended
/// as "and NN Paise". Zero → "Zero Rupees only".
library;

const List<String> _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
  'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
  'Seventeen', 'Eighteen', 'Nineteen',
];

const List<String> _tens = [
  '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty',
  'Ninety',
];

/// Words for a number 0–999 (no leading/trailing spaces).
String _threeDigits(int n) {
  final parts = <String>[];
  final hundreds = n ~/ 100;
  final rest = n % 100;
  if (hundreds > 0) {
    parts.add('${_ones[hundreds]} Hundred');
  }
  if (rest > 0) {
    if (rest < 20) {
      parts.add(_ones[rest]);
    } else {
      final t = _tens[rest ~/ 10];
      final o = rest % 10;
      parts.add(o > 0 ? '$t ${_ones[o]}' : t);
    }
  }
  return parts.join(' ');
}

/// Words for a whole number using the Indian system (Crore/Lakh/Thousand).
String _indianWords(int n) {
  if (n == 0) return 'Zero';
  final segments = <String>[];

  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  final hundredsBlock = n; // 0–999

  if (crore > 0) segments.add('${_indianWords(crore)} Crore');
  if (lakh > 0) segments.add('${_threeDigits(lakh)} Lakh');
  if (thousand > 0) segments.add('${_threeDigits(thousand)} Thousand');
  if (hundredsBlock > 0) segments.add(_threeDigits(hundredsBlock));

  return segments.join(' ');
}

/// Full invoice-style amount in words. [amount] is in rupees (paise as the
/// fractional part).
String amountToWords(double amount) {
  if (amount.isNaN || amount.isInfinite) return '';
  final negative = amount < 0;
  final abs = amount.abs();

  final rupees = abs.floor();
  // Round paise to avoid float drift (e.g. 0.1+0.2); clamp to 0–99.
  var paise = ((abs - rupees) * 100).round();
  var rupeesAdjusted = rupees;
  if (paise == 100) {
    paise = 0;
    rupeesAdjusted += 1;
  }

  final sb = StringBuffer();
  if (negative) sb.write('Minus ');
  sb.write(_indianWords(rupeesAdjusted));
  sb.write(' Rupees');
  if (paise > 0) {
    sb.write(' and ${_indianWords(paise)} Paise');
  }
  sb.write(' only');
  return sb.toString();
}
