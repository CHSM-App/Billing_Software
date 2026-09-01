import 'package:flutter_test/flutter_test.dart';
import 'package:Vittam/core/update/windows_update_io.dart';

/// Guards the Windows self-update decision: a bad compare either nags users
/// forever or silently never ships them a fix.
void main() {
  const url = 'https://example.com/VittamSetup.exe';

  test('newer manifest version offers the installer', () {
    final s = parseManifest({'version': '1.2.0', 'url': url}, '1.1.10');
    expect(s.updateAvailable, isTrue);
    expect(s.downloadUrl, url);
    expect(s.forceUpdate, isFalse);
  });

  test('same or older version is up to date', () {
    expect(parseManifest({'version': '1.1.10', 'url': url}, '1.1.10')
        .updateAvailable, isFalse);
    expect(parseManifest({'version': '1.1.9', 'url': url}, '1.1.10')
        .updateAvailable, isFalse);
  });

  test('missing url or unparseable version never prompts', () {
    expect(parseManifest({'version': '1.2.0'}, '1.1.10').updateAvailable,
        isFalse);
    expect(parseManifest({'version': 'nightly', 'url': url}, '1.1.10')
        .updateAvailable, isFalse);
    expect(parseManifest({}, '1.1.10').updateAvailable, isFalse);
  });

  test('force flag carries through', () {
    final s =
        parseManifest({'version': '2.0.0', 'url': url, 'force': true}, '1.1.10');
    expect(s.forceUpdate, isTrue);
  });
}
