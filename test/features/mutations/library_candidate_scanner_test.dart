import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/features/mutations/library_candidate_scanner.dart';

void main() {
  const scanner = LibraryCandidateScanner();

  test('prefers NICNT metadata and builds a validated candidate', () async {
    final directory = await Directory.systemTemp.createTemp('klm-candidate-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/Library.nicnt').writeAsString(
      _productHints(name: 'Test Library', regKey: 'Test Library', snpid: 'za6'),
    );
    await File('${directory.path}/Ignored_info.nkx').writeAsString(
      _productHints(name: 'Ignored', regKey: 'Ignored', snpid: 'DEF'),
    );

    final candidates = await scanner.scanDirectory(directory.path);

    expect(candidates, hasLength(1));
    expect(candidates.single.metadata.name, 'Test Library');
    expect(candidates.single.metadata.snpid, 'za6');
    expect(candidates.single.metadataPath, endsWith('Library.nicnt'));
    expect(candidates.single.productHintsXml, contains('<ProductHints>'));
    expect(candidates.single.productHintsXml, contains('<SNPID>za6</SNPID>'));
    expect(candidates.single.toUpsertRequest()['snpid'], 'za6');
    expect(candidates.single.toUpsertRequest().keys, isNot(contains('target')));
  });

  test('rejects a folder without Kontakt metadata', () async {
    final directory = await Directory.systemTemp.createTemp('klm-empty-');
    addTearDown(() => directory.delete(recursive: true));

    expect(
      () => scanner.scanDirectory(directory.path),
      throwsA(isA<LibraryCandidateException>()),
    );
  });

  test('rejects Reaktor content even when it uses ProductHints', () async {
    final directory = await Directory.systemTemp.createTemp('klm-reaktor-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/Reaktor.nicnt').writeAsString('''
<ProductHints><Product>
  <Name>Reaktor Library</Name><RegKey>Reaktor Library</RegKey><SNPID>R01</SNPID>
  <Type>Content</Type><PoweredBy>Reaktor</PoweredBy>
  <Relevance><Application>Reaktor</Application></Relevance>
</Product></ProductHints>
''');

    expect(
      () => scanner.scanDirectory(directory.path),
      throwsA(isA<LibraryCandidateException>()),
    );
  });

  test(
    'accepts Kontakt libraries powered by another Native Instruments app',
    () async {
      final directory = await Directory.systemTemp.createTemp('klm-maschine-');
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/Noire.nicnt').writeAsString('''
<ProductHints spec="1.0.16"><Product version="1">
  <Name>Noire</Name><Type>Content</Type>
  <Relevance><Application minVersion="5.6.8.0">kontakt</Application></Relevance>
  <PoweredBy>Maschine</PoweredBy><SNPID>K07</SNPID><RegKey>Noire</RegKey>
  <Icon>kontakt</Icon>
</Product></ProductHints>
''');

      final candidates = await scanner.scanDirectory(directory.path);

      expect(candidates.single.metadata.name, 'Noire');
      expect(candidates.single.metadata.applications, contains('kontakt'));
    },
  );

  test('rejects unsafe names before creating a mutation request', () async {
    final directory = await Directory.systemTemp.createTemp('klm-unsafe-');
    addTearDown(() => directory.delete(recursive: true));
    await File('${directory.path}/Unsafe.nicnt').writeAsString(
      _productHints(name: '../Escape', regKey: 'Escape', snpid: 'ABC'),
    );

    expect(() => scanner.scanDirectory(directory.path), throwsA(anything));
  });

  test('rejects duplicate identities in a batch', () async {
    final first = await Directory.systemTemp.createTemp('klm-batch-a-');
    final second = await Directory.systemTemp.createTemp('klm-batch-b-');
    addTearDown(() => first.delete(recursive: true));
    addTearDown(() => second.delete(recursive: true));
    final xml = _productHints(
      name: 'Duplicate',
      regKey: 'Duplicate',
      snpid: 'ABC',
    );
    await File('${first.path}/First.nicnt').writeAsString(xml);
    await File('${second.path}/Second.nicnt').writeAsString(xml);

    expect(
      () => scanner.scanDirectories([first.path, second.path]),
      throwsA(isA<LibraryCandidateException>()),
    );
  });
}

String _productHints({
  required String name,
  required String regKey,
  required String snpid,
}) {
  return '''
<ProductHints><Product>
  <Name>$name</Name><RegKey>$regKey</RegKey><SNPID>$snpid</SNPID>
  <Type>Content</Type><PoweredBy>Kontakt</PoweredBy>
  <ProductSpecific><Visibility>3</Visibility></ProductSpecific>
</Product></ProductHints>
''';
}
