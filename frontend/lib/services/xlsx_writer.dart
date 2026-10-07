import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builds a single-sheet .xlsx workbook.
///
/// An .xlsx is a zip of a few XML parts, so this writes them directly rather
/// than pulling in the `excel` package (which pins archive 3 and clashes with
/// the archive 4 the rest of the app resolves).
///
/// [rows] first row is the header: bold, and frozen while scrolling.
/// Cell values: `int` → plain number, `double` → number shown as `#,##0.00`
/// (so money columns sum in Excel), anything else → text. `null` → empty.
Uint8List buildXlsx({
  required String sheetName,
  required List<List<Object?>> rows,
  List<double>? colWidths,
}) {
  final sheet = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write('<worksheet xmlns="$_ns">')
    ..write('<sheetViews><sheetView workbookViewId="0">'
        '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
        '</sheetView></sheetViews>');
  if (colWidths != null && colWidths.isNotEmpty) {
    sheet.write('<cols>');
    for (var i = 0; i < colWidths.length; i++) {
      sheet.write('<col min="${i + 1}" max="${i + 1}" '
          'width="${colWidths[i]}" customWidth="1"/>');
    }
    sheet.write('</cols>');
  }
  sheet.write('<sheetData>');
  for (var r = 0; r < rows.length; r++) {
    sheet.write('<row r="${r + 1}">');
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null) continue;
      final ref = '${_column(c)}${r + 1}';
      if (r == 0) {
        sheet.write('<c r="$ref" t="inlineStr" s="1"><is><t>${_esc('$v')}</t></is></c>');
      } else if (v is int) {
        sheet.write('<c r="$ref"><v>$v</v></c>');
      } else if (v is double && v.isFinite) {
        sheet.write('<c r="$ref" s="2"><v>$v</v></c>');
      } else {
        sheet.write('<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
            '${_esc('$v')}</t></is></c>');
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');

  final archive = Archive()
    ..add(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..add(ArchiveFile.string('_rels/.rels', _rootRels))
    ..add(ArchiveFile.string('xl/workbook.xml', _workbook(_sheetName(sheetName))))
    ..add(ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels))
    ..add(ArchiveFile.string('xl/styles.xml', _styles))
    ..add(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet.toString()));
  return ZipEncoder().encodeBytes(archive);
}

/// 0 → A, 25 → Z, 26 → AA.
String _column(int i) {
  var s = '';
  for (var n = i + 1; n > 0; n = (n - 1) ~/ 26) {
    s = String.fromCharCode(65 + (n - 1) % 26) + s;
  }
  return s;
}

// Control characters other than tab/newline are illegal in XML and would make
// Excel refuse the whole file, so they are dropped rather than escaped.
final _illegalXml = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

String _esc(String s) => s
    .replaceAll(_illegalXml, '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Excel sheet names: at most 31 chars, none of []:*?/\
String _sheetName(String s) {
  final clean = s.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final name = clean.isEmpty ? 'Sheet1' : clean;
  return _esc(name.length > 31 ? name.substring(0, 31) : name);
}

const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships';

const _contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';

const _rootRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="$_pkgRel">'
    '<Relationship Id="rId1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(String sheetName) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="$_ns" xmlns:r="$_rel">'
    '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>';

const _workbookRels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="$_pkgRel">'
    '<Relationship Id="rId1" Type="$_rel/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="$_rel/styles" Target="styles.xml"/>'
    '</Relationships>';

// Cell styles: 0 = default, 1 = bold (header), 2 = #,##0.00 (built-in fmt 4).
const _styles = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="$_ns">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="3">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '</cellXfs>'
    '</styleSheet>';
