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
