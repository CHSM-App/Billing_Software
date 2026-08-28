import 'package:Vittam/widgets/app_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Picking a customer must fill BOTH fields, whichever list it came from.
///
/// These exercise the real [AppTextField] configuration the billing screen
/// uses — `capitalizeWords` on the name, `digitsOnly` + `maxLength: 10` on the
/// phone — because those formatters are the plausible way a programmatic write
/// gets mangled or dropped.
class _Harness extends StatefulWidget {
  final void Function(TextEditingController name, TextEditingController phone)
      onReady;
  const _Harness({required this.onReady});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final name = TextEditingController();
  final phone = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onReady(name, phone);
    return MaterialApp(
      home: Scaffold(
        body: Column(children: [
          AppTextField(
            label: 'Customer name',
            controller: name,
            capitalizeWords: true,
          ),
          AppTextField(
            label: 'Customer phone',
            controller: phone,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ]),
      ),
    );
  }
}

/// The exact write [_applyCustomerSuggestion] performs.
void applySuggestion(
  TextEditingController name,
  TextEditingController phone, {
  required String suggestedName,
  required String suggestedPhone,
}) {
  final digits = suggestedPhone.replaceAll(RegExp(r'\D'), '');
  final local =
      digits.length > 10 ? digits.substring(digits.length - 10) : digits;

  if (suggestedName.isNotEmpty) {
    name.value = TextEditingValue(
      text: suggestedName,
      selection: TextSelection.collapsed(offset: suggestedName.length),
    );
  }
  if (local.isNotEmpty) {
    phone.value = TextEditingValue(
      text: local,
      selection: TextSelection.collapsed(offset: local.length),
    );
  }
}

void main() {
  group('customer suggestion fill', () {
    late TextEditingController name;
    late TextEditingController phone;

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(_Harness(onReady: (n, p) {
        name = n;
        phone = p;
      }));
      await tester.pumpAndSettle();
    }

    testWidgets('picking from the NAME list fills the phone too',
        (tester) async {
      await pump(tester);
      // The user typed a name, so only that field has content.
      name.text = 'Ram';
      await tester.pump();

      applySuggestion(name, phone,
          suggestedName: 'Ramesh Kumar', suggestedPhone: '9876543210');
      await tester.pump();

      expect(name.text, 'Ramesh Kumar');
      expect(phone.text, '9876543210',
          reason: 'the phone must arrive with the name');
    });

    testWidgets('picking from the PHONE list fills the name too',
        (tester) async {
      await pump(tester);
      phone.text = '98765';
      await tester.pump();

      applySuggestion(name, phone,
          suggestedName: 'Ramesh Kumar', suggestedPhone: '9876543210');
      await tester.pump();

      expect(name.text, 'Ramesh Kumar',
          reason: 'the name must arrive with the phone');
      expect(phone.text, '9876543210');
    });

    testWidgets('a stored country prefix is trimmed to 10 digits',
        (tester) async {
      await pump(tester);

      applySuggestion(name, phone,
          suggestedName: 'Sagar', suggestedPhone: '+91 82628 78298');
      await tester.pump();

      expect(phone.text, '8262878298',
          reason: 'maxLength:10 would otherwise clip the WRONG end');
      expect(phone.text.length, 10);
    });

    testWidgets('a customer with no stored name leaves the name untouched',
        (tester) async {
      await pump(tester);
      name.text = 'Walk-in';
      await tester.pump();

      applySuggestion(name, phone,
          suggestedName: '', suggestedPhone: '9876543210');
      await tester.pump();

      expect(name.text, 'Walk-in',
          reason: 'an empty suggestion must not wipe what was typed');
      expect(phone.text, '9876543210');
    });

    testWidgets('the caret lands after the text, not at offset 0',
        (tester) async {
      await pump(tester);

      applySuggestion(name, phone,
          suggestedName: 'Ramesh Kumar', suggestedPhone: '9876543210');
      await tester.pump();

      expect(name.selection.baseOffset, 'Ramesh Kumar'.length);
      expect(phone.selection.baseOffset, 10);
    });
  });
}
