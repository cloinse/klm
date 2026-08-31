import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';
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

  test(
    'skips folders without metadata and installs the rest of a batch',
    () async {
      final library = await Directory.systemTemp.createTemp('klm-batch-ok-');
      final empty = await Directory.systemTemp.createTemp('klm-batch-empty-');
      addTearDown(() => library.delete(recursive: true));
      addTearDown(() => empty.delete(recursive: true));
      await File('${library.path}/Piano.nicnt').writeAsString(
        _productHints(name: 'Piano', regKey: 'Piano', snpid: 'p01'),
      );

      final result = await scanner.scanDirectories([library.path, empty.path]);

      expect(result.candidates, hasLength(1));
      expect(result.candidates.single.metadata.name, 'Piano');
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.path, empty.path);
      expect(
        result.skipped.single.reason,
        LibraryCandidateSkipReason.missingMetadata,
      );
    },
  );

  test('discovers nested libraries under a parent folder', () async {
    final root = await Directory.systemTemp.createTemp('klm-nested-');
    addTearDown(() => root.delete(recursive: true));
    final first = await Directory('${root.path}/First').create();
    final second = await Directory(
      '${root.path}/Vendor/Second',
    ).create(recursive: true);
    await Directory('${root.path}/Samples').create();
    await File('${first.path}/First.nicnt').writeAsString(
      _productHints(name: 'First', regKey: 'First', snpid: 'n01'),
    );
    await File('${second.path}/Second.nicnt').writeAsString(
      _productHints(name: 'Second', regKey: 'Second', snpid: 'n02'),
    );

    final result = await scanner.scanDirectories([root.path]);

    expect(
      result.candidates.map((candidate) => candidate.metadata.name).toSet(),
      {'First', 'Second'},
    );
    expect(result.skipped, isEmpty);
  });

  test('points ContentDir at the library root when NICNT is nested', () async {
    final library = await Directory.systemTemp.createTemp('klm-content-root-');
    addTearDown(() => library.delete(recursive: true));
    await Directory('${library.path}/Instruments').create();
    final docs = await Directory('${library.path}/Documentation').create();
    await File('${docs.path}/Nested.nicnt').writeAsString(
      _productHints(name: 'Nested', regKey: 'Nested', snpid: 'n03'),
    );

    final candidates = await scanner.scanDirectory(docs.path);

    expect(candidates.single.contentPath, await library.resolveSymbolicLinks());
  });

  test(
    'keeps ContentDir on the metadata folder when it already has content',
    () async {
      final library = await Directory.systemTemp.createTemp(
        'klm-content-keep-',
      );
      addTearDown(() => library.delete(recursive: true));
      await Directory('${library.path}/Instruments').create();
      await File('${library.path}/Library.nicnt').writeAsString(
        _productHints(name: 'Root Lib', regKey: 'Root Lib', snpid: 'n04'),
      );

      final candidates = await scanner.scanDirectory(library.path);

      expect(
        candidates.single.contentPath,
        await library.resolveSymbolicLinks(),
      );
    },
  );

  test('scanDirectories returns empty when the picker is cancelled', () async {
    final result = await scanner.scanDirectories(const []);
    expect(result.candidates, isEmpty);
    expect(result.skipped, isEmpty);
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
