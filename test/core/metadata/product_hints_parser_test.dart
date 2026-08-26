import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/metadata/product_hints_parser.dart';

void main() {
  const parser = ProductHintsParser();

  test('extrae ProductHints desde un archivo binario', () {
    final bytes = utf8.encode('''
ruido binario
<ProductHints>
  <Product>
    <Name>Analog Dreams</Name>
    <RegKey>Analog Dreams</RegKey>
    <SNPID>aBc</SNPID>
    <ProductSpecific>
      <Visibility>3</Visibility><HU>hu</HU><JDX>jdx</JDX>
    </ProductSpecific>
    <UPID>upid</UPID><AuthSystem>RAS3</AuthSystem>
    <Relevance><Application minVersion="7.2">Kontakt</Application></Relevance>
  </Product>
</ProductHints>
otros datos
''');

    final metadata = parser.parseBytes(bytes);

    expect(metadata.name, 'Analog Dreams');
    expect(metadata.regKey, 'Analog Dreams');
    expect(metadata.snpid, 'aBc');
    expect(metadata.visibility, 3);
    expect(metadata.minimumKontaktVersion, '7.2');
  });

  test('preserva la capitalización del SNPID en metadata y ProductHints', () {
    const xml = '''
<ProductHints><Product><Name>A</Name><RegKey>A</RegKey><SNPID>a1b</SNPID></Product></ProductHints>
''';

    final document = parser.parseDocumentText(xml);

    expect(document.metadata.snpid, 'a1b');
    expect(document.xml, contains('<SNPID>a1b</SNPID>'));
  });

  test('preserva la declaración XML de ProductHints', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<ProductHints><Product><Name>A</Name><RegKey>A</RegKey><SNPID>a1b</SNPID></Product></ProductHints>
''';

    final document = parser.parseDocumentText(xml);

    expect(
      document.xml,
      startsWith('<?xml version="1.0" encoding="UTF-8" standalone="no" ?>'),
    );
  });

  test('uses ProductSpecific visibility for the Windows registry', () {
    const xml = '''
<ProductHints spec="1.0.16">
  <Product version="1">
    <Name>S90 ES</Name>
    <Type>Content</Type>
    <PoweredBy>Kontakt</PoweredBy>
    <Visibility>7</Visibility>
    <Company>Native Instruments GmbH</Company>
    <AuthSystem>RAS2</AuthSystem>
    <SNPID>ZA1</SNPID>
    <RegKey>S90 ES</RegKey>
    <Icon>kontakt</Icon>
    <ProductSpecific>
      <HU>6B70EC16E02410D1A515685C1001D559</HU>
      <JDX>023730940B73318EAEAD916E3989EC68BE72599A2F1738F828A7D028C9B1ECCA</JDX>
      <Visibility type="Number">3</Visibility>
    </ProductSpecific>
  </Product>
</ProductHints>
''';

    final document = parser.parseDocumentText(xml);

    expect(document.metadata.visibility, 3);
    expect(document.xml, contains('<Visibility>7</Visibility>'));
    expect(document.xml, contains('<Visibility type="Number">3</Visibility>'));
  });

  test('classifies Kontakt content separately from third-party plugins', () {
    const kontaktXml = '''
<ProductHints><Product>
  <Name>Noire</Name><RegKey>Noire</RegKey><SNPID>K07</SNPID>
  <Type>Content</Type><Company>Native Instruments GmbH</Company>
  <Relevance><Application minVersion="6.0">Kontakt</Application></Relevance>
</Product></ProductHints>
''';
    const pluginXml = '''
<ProductHints><Product>
  <Name>Arturia Plugin</Name><RegKey>Arturia Plugin</RegKey><SNPID>A01</SNPID>
  <Type>Plugin</Type><Company>Arturia</Company>
  <Relevance><Application>Kontakt</Application><Application>Maschine</Application></Relevance>
</Product></ProductHints>
''';

    final kontakt = parser.parseText(kontaktXml);
    final plugin = parser.parseText(pluginXml);

    expect(kontakt.productType, 'Content');
    expect(kontakt.company, 'Native Instruments GmbH');
    expect(kontakt.applications, contains('kontakt'));
    expect(kontakt.isKontaktLibraryMetadata, isTrue);
    expect(plugin.applications, containsAll(['kontakt', 'maschine']));
    expect(plugin.isKontaktLibraryMetadata, isFalse);
  });

  test('accepts legacy Kontakt content without an Application element', () {
    const xml = '''
<ProductHints><Product>
  <Name>Legacy Library</Name><RegKey>Legacy Library</RegKey><SNPID>ZA1</SNPID>
  <Type>Content</Type><Company>Legacy Developer</Company>
</Product></ProductHints>
''';

    final metadata = parser.parseText(xml);

    expect(metadata.applications, isEmpty);
    expect(metadata.isKontaktLibraryMetadata, isTrue);
  });

  test('uses engine markers to exclude non-Kontakt content', () {
    const reaktorXml = '''
<ProductHints><Product>
  <Name>Reaktor Factory Library</Name><RegKey>Reaktor Factory Library</RegKey><SNPID>R01</SNPID>
  <Type>Content</Type><PoweredBy>Reaktor</PoweredBy><Icon>reaktor</Icon>
  <Relevance><Application>Reaktor</Application></Relevance>
</Product></ProductHints>
''';
    const poweredByKontaktXml = '''
<ProductHints><Product>
  <Name>Legacy Kontakt Library</Name><RegKey>Legacy Kontakt Library</RegKey><SNPID>K01</SNPID>
  <PoweredBy>Kontakt</PoweredBy><Icon>kontakt</Icon>
</Product></ProductHints>
''';

    final reaktor = parser.parseText(reaktorXml);
    final kontakt = parser.parseText(poweredByKontaktXml);

    expect(reaktor.poweredBy, 'Reaktor');
    expect(reaktor.icon, 'reaktor');
    expect(reaktor.isKontaktLibraryMetadata, isFalse);
    expect(kontakt.poweredBy, 'Kontakt');
    expect(kontakt.icon, 'kontakt');
    expect(kontakt.isKontaktLibraryMetadata, isTrue);
  });

  test('rechaza metadata sin campos obligatorios', () {
    const xml =
        '<ProductHints><Product><Name>A</Name></Product></ProductHints>';

    expect(() => parser.parseText(xml), throwsA(isA<ProductHintsException>()));
  });

  test('rechaza nombres que podrían escapar de las rutas de registro', () {
    const xml = '''
<ProductHints><Product><Name>../Library</Name><RegKey>A</RegKey><SNPID>ABC</SNPID></Product></ProductHints>
''';

    expect(() => parser.parseText(xml), throwsA(isA<ProductHintsException>()));
  });
}
