import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/platform/app_update_platform.dart';

void main() {
  const signedUpdate = '''
<rss version="2.0"
  xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>5</sparkle:version>
      <sparkle:shortVersionString>0.1.4</sparkle:shortVersionString>
      <enclosure
        url="https://github.com/cloinse/klm/releases/download/v0.1.4/setup.exe"
        sparkle:os="windows-x64"
        sparkle:edSignature="signed" />
    </item>
  </channel>
</rss>
''';

  test('Windows appcast detects a newer signed build', () {
    expect(
      windowsAppcastHasNewerUpdate(
        signedUpdate,
        currentVersion: '0.1.3',
        currentBuild: '4',
      ),
      isTrue,
    );
  });

  test('Windows appcast ignores the current build', () {
    expect(
      windowsAppcastHasNewerUpdate(
        signedUpdate,
        currentVersion: '0.1.4',
        currentBuild: '5',
      ),
      isFalse,
    );
  });

  test('Windows appcast ignores unsigned or non-Windows payloads', () {
    final invalid = signedUpdate
        .replaceFirst('sparkle:os="windows-x64"', 'sparkle:os="macos"')
        .replaceFirst('sparkle:edSignature="signed"', '');
    expect(
      windowsAppcastHasNewerUpdate(
        invalid,
        currentVersion: '0.1.3',
        currentBuild: '4',
      ),
      isFalse,
    );
  });
}
