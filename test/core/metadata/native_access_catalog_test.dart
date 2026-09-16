import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/metadata/native_access_catalog.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';

void main() {
  test('indexes Kontakt catalog products and ignores plugins', () {
    const catalog = '''
<ProductHints>
  <Product>
    <Name>Session Guitarist - Electric Mint</Name>
    <RegKey>Session Guitarist - Electric Mint</RegKey>
    <SNPID>K54</SNPID>
    <Type>Content</Type>
    <Relevance><Application>Kontakt</Application></Relevance>
  </Product>
  <Product>
    <Name>Arturia Plugin</Name>
    <RegKey>Arturia Plugin</RegKey>
    <SNPID>A01</SNPID>
    <Type>Plugin</Type>
    <Relevance><Application>Kontakt</Application></Relevance>
  </Product>
</ProductHints>
''';

    final index = NativeAccessCatalog.parse(catalog);

    expect(
      index
          .find(name: 'Session Guitarist - Electric Mint')
          ?.isKontaktLibraryMetadata,
      isTrue,
    );
    expect(index.find(name: 'Arturia Plugin'), isNull);
    expect(index.find(name: 'Missing Library'), isNull);
  });

  test('does not override libraries that already have individual XML', () {
    final catalog = NativeAccessCatalog.parse('''
<ProductHints>
  <Product>
    <Name>FANTHASY</Name>
    <RegKey>FANTHASY</RegKey>
    <SNPID>za8</SNPID>
    <Type>Content</Type>
    <Relevance><Application>Kontakt</Application></Relevance>
  </Product>
</ProductHints>
''');
    const library = KontaktLibrary(
      id: 'fanthasy',
      name: 'FANTHASY',
      regKey: 'FANTHASY',
      snpid: 'za8',
      sources: {RegistrationSource.serviceCenter},
    );

    final applied = catalog.applyTo(const [library]).single;

    expect(applied.sources, equals({RegistrationSource.serviceCenter}));
    expect(applied.hasNativeAccessCatalog, isFalse);
  });

  test('covers discovered libraries that match the catalog', () {
    final catalog = NativeAccessCatalog.parse('''
<ProductHints>
  <Product>
    <Name>Session Guitarist - Electric Mint</Name>
    <RegKey>Session Guitarist - Electric Mint</RegKey>
    <SNPID>K54</SNPID>
    <Type>Content</Type>
    <Relevance><Application minVersion="6.7.0">Kontakt</Application></Relevance>
  </Product>
</ProductHints>
''');
    const library = KontaktLibrary(
      id: 'mint',
      name: 'Session Guitarist - Electric Mint',
      sources: {RegistrationSource.installedProducts},
    );

    final applied = catalog.applyTo(const [library]).single;

    expect(applied.hasNativeAccessCatalog, isTrue);
    expect(applied.snpid, 'K54');
    expect(applied.minimumKontaktVersion, '6.7.0');
  });
}
