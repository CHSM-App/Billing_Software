import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/services/printer_service_native.dart';

void main() {
  test('network printer address parses to host + port, 9100 by default', () {
    expect(PrinterService.parseHostPort('192.168.1.50:9100'),
        ('192.168.1.50', 9100));
    expect(PrinterService.parseHostPort(' 192.168.223.1 '),
        ('192.168.223.1', 9100));
    expect(PrinterService.parseHostPort('CN811-UEWB-12CF:9200'),
        ('CN811-UEWB-12CF', 9200));
    expect(PrinterService.parseHostPort('10.0.0.5:abc'), ('10.0.0.5', 9100));
  });

  test('network printer survives a save/load round trip', () {
    const p = Printer(
        name: 'Counter',
        address: '192.168.1.50:9100',
        connectionType: ConnectionType.network);
    final back = Printer.fromJson(p.toJson());
    expect(back.connectionType, ConnectionType.network);
    expect(back.address, '192.168.1.50:9100');
  });
}
