import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/platform/macos/macos_content_path.dart';

void main() {
  test('keeps POSIX content paths', () {
    expect(
      posixContentPath(
        '/Users/Shared/Session Guitarist - Electric Mint Library',
      ),
      '/Users/Shared/Session Guitarist - Electric Mint Library',
    );
    expect(posixContentPath('/Users/Shared/Library/'), '/Users/Shared/Library');
  });

  test('converts HFS installer ContentDir values', () {
    expect(
      posixContentPath(
        'Macintosh HD:Users:Shared:Session Guitarist - Electric Mint Library:',
      ),
      '/Users/Shared/Session Guitarist - Electric Mint Library',
    );
    expect(
      posixContentPath('External SSD:Libraries:Piano:'),
      '/Volumes/External SSD/Libraries/Piano',
    );
    expect(
      posixContentPath('/:Applications:Waves:Data:NKS FX:CLA-76:'),
      '/Applications/Waves/Data/NKS FX/CLA-76',
    );
  });

  test('returns null for empty values', () {
    expect(posixContentPath(null), isNull);
    expect(posixContentPath('   '), isNull);
    expect(posixContentPath('Macintosh HD:'), isNull);
  });
}
