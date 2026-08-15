import 'package:flutter/services.dart';

/// Capitalizes the first letter of each word as the user types.
/// Works on any input method (including physical keyboards on desktop),
/// unlike [TextCapitalization] which only hints virtual keyboards.
class CapitalizeWordsFormatter extends TextInputFormatter {
  const CapitalizeWordsFormatter();

  static final _letter = RegExp(r'[a-zA-Z]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool capitalizeNext = true;
    for (final char in text.split('')) {
      if (capitalizeNext && _letter.hasMatch(char)) {
        buffer.write(char.toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(char);
        capitalizeNext = char == ' ';
      }
    }

    return newValue.copyWith(text: buffer.toString());
  }
}

/// Forces input to upper case as the user types. Used for GSTIN and PAN, whose
/// formats are defined in capitals — without this a lower-case entry fails
/// validation even though the value is otherwise correct.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    if (upper == newValue.text) return newValue;
    return newValue.copyWith(text: upper);
  }
}
