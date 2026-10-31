import 'package:flutter/services.dart';

/// Indian mobile number: 10 digits starting 6–9. Same rule as isIndianMobile()
/// in backend/src/validate.js. Login keeps the looser 10-digit check so an
/// account made before this rule can still sign in.
bool isIndianMobile(String v) => RegExp(r'^[6-9]\d{9}$').hasMatch(v.trim());

/// The shop's own phone: a mobile, or a landline with its STD code (0 + 10
/// digits, spaces/hyphens allowed: 02366-262626). Only the business phone
/// takes landlines — logins, staff and customers get OTPs/WhatsApp, so they
/// stay [isIndianMobile]. Same rule as isBusinessPhone() in validate.js.
bool isBusinessPhone(String v) =>
    isIndianMobile(v) ||
    RegExp(r'^0[1-9]\d{9}$').hasMatch(v.trim().replaceAll(RegExp(r'[\s-]'), ''));

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
