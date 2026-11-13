import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/services/stock_report_export.dart';

void main() {
  test('stock rows carry opening, movements and closing as numbers', () {
    final rows = StockReportExport.stockRows([
      {'name': 'Beer', 'unit': 'btl', 'opening': '90', 'purchased': 50, 'sold': 0,
       'returned': 0, 'adjusted': 0, 'closing': 140},
    ]);
    expect(rows.first, contains('Closing'));
    expect(rows[1], ['Beer', 'btl', 90.0, 50.0, 0.0, 140.0]);
    // The PDF drops the Unit column.
    expect(StockReportExport.stockRows([{'name': 'Beer', 'unit': 'btl'}], unit: false).first,
        ['Item', 'Opening', 'Purchased', 'Sold', 'Closing']);
  });

  test('profit rows: buy 70, sell 100, 10 sold = 300 profit, 30 per unit', () {
    final rows = StockReportExport.profitRows([
      {'name': 'Beer', 'qty': 10, 'sales': 1000, 'avg_cost': 70, 'avg_sell': 100,
       'profit': 300, 'margin_pct': 30, 'qty_no_cost': 0},
      {'name': 'Wine', 'qty': 2, 'sales': 400, 'avg_cost': null, 'avg_sell': null,
       'profit': 0, 'margin_pct': null, 'qty_no_cost': 2},
    ]);
    expect(rows[1][5], 30.0);
    expect(rows[1][6], 300.0);
    expect(rows[2][3], ''); // unknown cost is blank, not zero
  });
}
