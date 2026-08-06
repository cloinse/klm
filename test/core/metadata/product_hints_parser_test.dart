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
    expect(metadata.snpid, 'ABC');
    expect(metadata.visibility, 3);
    expect(metadata.minimumKontaktVersion, '7.2');
  });

  test('normaliza el SNPID también en el XML de ProductHints', () {
    const xml = '''
<ProductHints><Product><Name>A</Name><RegKey>A</RegKey><SNPID>a1b</SNPID></Product></ProductHints>
''';

    final document = parser.parseDocumentText(xml);

    expect(document.metadata.snpid, 'A1B');
    expect(document.xml, contains('<SNPID>A1B</SNPID>'));
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
