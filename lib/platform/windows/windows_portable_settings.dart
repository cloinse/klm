import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:kontakt_library_manager/core/models/kontakt_mutation.dart';

class WindowsPortableSupport extends ChangeNotifier {
  WindowsPortableSupport._(this._preferences, this._enabled, this._rootPath);

  static const _enabledKey = 'windows_portable_enabled';
  static const _rootPathKey = 'windows_portable_root_path';

  final SharedPreferences? _preferences;
  bool _enabled;
  String? _rootPath;

  factory WindowsPortableSupport({
    SharedPreferences? preferences,
    bool enabled = false,
    String? rootPath,
  }) {
    return WindowsPortableSupport._(preferences, enabled, rootPath);
  }

  static Future<WindowsPortableSupport> load() async {
    final preferences = await SharedPreferences.getInstance();
    return WindowsPortableSupport._(
      preferences,
      preferences.getBool(_enabledKey) ?? false,
      _clean(preferences.getString(_rootPathKey)),
    );
  }

  bool get enabled => _enabled;
  String? get rootPath => _rootPath;
  bool get isActive => _enabled && _rootPath != null;

  String? get settingsPath {
    final root = _rootPath;
    if (root == null) return null;
    return _join(root, r'UserData\Settings.cfg');
  }

  Future<void> configure({required bool enabled, String? rootPath}) async {
    _enabled = enabled;
    _rootPath = _clean(rootPath ?? _rootPath);
    notifyListeners();
    await _preferences?.setBool(_enabledKey, _enabled);
    if (_rootPath == null) {
      await _preferences?.remove(_rootPathKey);
    } else {
      await _preferences?.setString(_rootPathKey, _rootPath!);
    }
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _join(String first, String second) {
    final separator = Platform.pathSeparator;
    final normalizedFirst = first.endsWith(separator)
        ? first.substring(0, first.length - separator.length)
        : first;
    final normalizedSecond = second.replaceAll(RegExp(r'[\\/]'), separator);
    return '$normalizedFirst$separator${normalizedSecond.replaceFirst(RegExp('^${RegExp.escape(separator)}+'), '')}';
  }
}

class PortableSettingsException implements Exception {
  const PortableSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PortableSettingsSnapshot {
  const PortableSettingsSnapshot({required this.exists, this.bytes});

  final bool exists;
  final List<int>? bytes;
}

class PortableSettingsRecord {
  const PortableSettingsRecord({
    required this.section,
    required this.name,
    required this.snpid,
    required this.contentPath,
    this.visibility,
    this.userListIndex,
    this.hu,
    this.jdx,
    this.upid,
    this.authSystem,
  });

  final String section;
  final String name;
  final String snpid;
  final String? contentPath;
  final int? visibility;
  final int? userListIndex;
  final String? hu;
  final String? jdx;
  final String? upid;
  final String? authSystem;
}

class PortableSettingsStore {
  PortableSettingsStore(this.rootPath);

  final String rootPath;

  String get settingsPath => _join(rootPath, r'UserData\Settings.cfg');

  Future<List<PortableSettingsRecord>> readRecords() async {
    final document = await _readDocument();
    return document.records;
  }

  String resolveContentPath(String value) {
    final trimmed = value.trim();
    if (_isWindowsAbsolutePath(trimmed)) {
      return trimmed.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator);
    }
    final normalized = _normalizePath(trimmed);
    if (normalized.isEmpty) return normalized;
    final relative = normalized.replaceFirst(RegExp(r'^\\+'), '');
    final candidate = _join(rootPath, relative);
    final directory = Directory(candidate);
    if (directory.existsSync()) {
      try {
        return directory.resolveSymbolicLinksSync();
      } catch (_) {
        return directory.absolute.path;
      }
    }
    return candidate;
  }

  Future<PortableSettingsSnapshot> snapshot() async {
    final file = File(settingsPath);
    if (!await file.exists()) {
      return const PortableSettingsSnapshot(exists: false);
    }
    return PortableSettingsSnapshot(
      exists: true,
      bytes: await file.readAsBytes(),
    );
  }

  Future<void> restore(PortableSettingsSnapshot snapshot) async {
    final file = File(settingsPath);
    if (!snapshot.exists) {
      if (await file.exists()) await file.delete();
      return;
    }
    final bytes = snapshot.bytes;
    if (bytes == null) {
      throw const PortableSettingsException(
        'El respaldo de Settings.cfg está incompleto.',
      );
    }
    await _writeBytes(bytes);
  }

  Future<void> upsert(KontaktLibraryCandidate candidate) async {
    final document = await _readDocument();
    final section = _findSection(document.lines, candidate.metadata);
    final values = <String, String>{
      'Name': _stringValue(candidate.metadata.name),
      'SNPID': _stringValue(candidate.metadata.snpid),
      'Company': _stringValue('Native Instruments GmbH'),
      'ContentDir': _stringValue(_portablePath(candidate.contentPath)),
      'Visibility': _dwordValue(candidate.metadata.visibility ?? 3),
      'UserRemoved': _dwordValue(0),
      if (candidate.metadata.hu != null)
        'HU': _stringValue(candidate.metadata.hu!),
      if (candidate.metadata.jdx != null)
        'JDX': _stringValue(candidate.metadata.jdx!),
      if (candidate.metadata.upid != null)
        'UPID': _stringValue(candidate.metadata.upid!),
      if (candidate.metadata.authSystem != null)
        'AuthSystem': _stringValue(candidate.metadata.authSystem!),
    };

    if (section == null) {
      _appendSection(document.lines, candidate.metadata.regKey, values);
    } else {
      for (final entry in values.entries) {
        _setSectionValue(document.lines, section, entry.key, entry.value);
      }
    }
    await _writeDocument(document);
  }

  Future<void> relocate(KontaktLibrary library, String contentPath) async {
    final document = await _readDocument();
    final section = _findSectionByLibrary(document.lines, library);
    if (section == null) {
      throw PortableSettingsException(
        'No se encontró la librería en $settingsPath.',
      );
    }
    _setSectionValue(
      document.lines,
      section,
      'ContentDir',
      _stringValue(_portablePath(contentPath)),
    );
    await _writeDocument(document);
  }

  Future<void> remove(KontaktLibrary library) async {
    final document = await _readDocument();
    final section = _findSectionByLibrary(document.lines, library);
    if (section == null) return;
    document.lines.removeRange(section.start, section.end);
    await _writeDocument(document);
  }

  Future<void> saveClassicOrder(List<KontaktLibrary> libraries) async {
    final document = await _readDocument();
    for (var index = 0; index < libraries.length; index++) {
      final section = _findSectionByLibrary(document.lines, libraries[index]);
      if (section == null) continue;
      _setSectionValue(
        document.lines,
        section,
        'UserListIndex',
        _dwordValue(index + 1),
      );
    }
    _setGlobalValue(document.lines, 'browserLibsAZSort', _dwordValue(0));
    await _writeDocument(document);
  }

  Future<_PortableDocument> _readDocument() async {
    final file = File(settingsPath);
    if (!await file.exists()) {
      throw PortableSettingsException('No se encontró $settingsPath.');
    }
    final bytes = await file.readAsBytes();
    var text = utf8.decode(bytes, allowMalformed: true);
    final hasBom = text.startsWith('\uFEFF');
    if (hasBom) text = text.substring(1);
    final lineEnding = text.contains('\r\n') ? '\r\n' : '\n';
    final hasFinalLineEnding = text.endsWith(lineEnding);
    var lines = text.split(lineEnding);
    if (hasFinalLineEnding && lines.isNotEmpty && lines.last.isEmpty) {
      lines = lines.sublist(0, lines.length - 1);
    }
    return _PortableDocument(
      lines: lines,
      lineEnding: lineEnding,
      hasFinalLineEnding: hasFinalLineEnding,
      hasBom: hasBom,
    );
  }

  Future<void> _writeDocument(_PortableDocument document) async {
    var text = document.lines.join(document.lineEnding);
    if (document.hasFinalLineEnding) text += document.lineEnding;
    if (document.hasBom) text = '\uFEFF$text';
    await _writeBytes(utf8.encode(text));
  }

  Future<void> _writeBytes(List<int> bytes) async {
    final file = File(settingsPath);
    await file.parent.create(recursive: true);
    final temporary = File(
      _join(
        file.parent.path,
        '.klm-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  _PortableSection? _findSection(List<String> lines, ProductMetadata metadata) {
    final byName = _sections(lines).where((section) {
      return _sectionValue(lines, section, 'Name')?.toLowerCase() ==
          metadata.name.toLowerCase();
    });
    return byName.firstOrNull ??
        _sections(lines)
            .where(
              (section) =>
                  section.name.toLowerCase() == metadata.regKey.toLowerCase(),
            )
            .firstOrNull;
  }

  _PortableSection? _findSectionByLibrary(
    List<String> lines,
    KontaktLibrary library,
  ) {
    final name = library.name.toLowerCase();
    final regKey = (library.regKey ?? '').toLowerCase();
    return _sections(lines).where((section) {
      final sectionName = _sectionValue(lines, section, 'Name')?.toLowerCase();
      return sectionName == name ||
          (regKey.isNotEmpty && section.name.toLowerCase() == regKey);
    }).firstOrNull;
  }

  List<_PortableSection> _sections(List<String> lines) {
    final sections = <_PortableSection>[];
    for (var index = 0; index < lines.length; index++) {
      final match = RegExp(r'^\[([^\]]+)\]\s*$').firstMatch(lines[index]);
      if (match == null) continue;
      sections.add(_PortableSection(match.group(1)!, index, lines.length));
    }
    for (var index = 0; index < sections.length - 1; index++) {
      sections[index].end = sections[index + 1].start;
    }
    return sections;
  }

  String? _sectionValue(
    List<String> lines,
    _PortableSection section,
    String key,
  ) {
    for (var index = section.start + 1; index < section.end; index++) {
      final pair = _keyValue(lines[index]);
      if (pair?.$1 == key) return _decodeValue(pair!.$2);
    }
    return null;
  }

  void _setSectionValue(
    List<String> lines,
    _PortableSection section,
    String key,
    String value,
  ) {
    final current = _sections(
      lines,
    ).firstWhere((item) => item.start == section.start);
    for (var index = current.start + 1; index < current.end; index++) {
      final pair = _keyValue(lines[index]);
      if (pair?.$1 == key) {
        lines[index] = '$key=$value';
        return;
      }
    }
    lines.insert(current.end, '$key=$value');
  }

  void _setGlobalValue(List<String> lines, String key, String value) {
    for (var index = 0; index < lines.length; index++) {
      final pair = _keyValue(lines[index]);
      if (pair?.$1 == key) {
        lines[index] = '$key=$value';
        return;
      }
    }
    lines.add('$key=$value');
  }

  void _appendSection(
    List<String> lines,
    String sectionName,
    Map<String, String> values,
  ) {
    _validateComponent(sectionName, 'RegKey');
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isNotEmpty) lines.add('');
    lines.add('[$sectionName]');
    for (final entry in values.entries) {
      lines.add('${entry.key}=${entry.value}');
    }
  }

  String _portablePath(String contentPath) {
    final normalizedRoot = _normalizePath(
      rootPath,
    ).replaceFirst(RegExp(r'\\+$'), '');
    final normalizedContent = _normalizePath(
      contentPath,
    ).replaceFirst(RegExp(r'\\+$'), '');
    final rootParts = _pathParts(normalizedRoot);
    final contentParts = _pathParts(normalizedContent);
    if (rootParts.isEmpty || contentParts.isEmpty) {
      throw const PortableSettingsException(
        'No se pudo convertir la ruta a un formato relativo.',
      );
    }
    var common = 0;
    while (common < rootParts.length &&
        common < contentParts.length &&
        rootParts[common].toLowerCase() == contentParts[common].toLowerCase()) {
      common++;
    }
    if (common == 0) {
      throw const PortableSettingsException(
        'La librería debe estar en la misma unidad que Kontakt Portable.',
      );
    }
    final relativeParts = <String>[
      for (var index = common; index < rootParts.length; index++) '..',
      ...contentParts.skip(common),
    ];
    final relative = relativeParts.isEmpty ? '.' : relativeParts.join('\\');
    return '.\\$relative';
  }

  String _normalizePath(String path) => path.replaceAll('/', '\\');

  List<String> _pathParts(String path) =>
      path.split('\\').where((part) => part.isNotEmpty).toList(growable: false);

  String _stringValue(String value) => 'sz:$value';
  String _dwordValue(int value) => 'dw:$value';

  String? _decodeValue(String raw) {
    if (raw.startsWith('sz:')) return raw.substring(3);
    if (raw.startsWith('dw:')) return raw.substring(3);
    return raw;
  }

  (String, String)? _keyValue(String line) {
    final separator = line.indexOf('=');
    if (separator <= 0) return null;
    return (line.substring(0, separator).trim(), line.substring(separator + 1));
  }

  void _validateComponent(String value, String field) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('[') ||
        value.contains(']') ||
        value.contains('\\') ||
        value.contains('/') ||
        value.contains('\n') ||
        value.contains('\r')) {
      throw PortableSettingsException('$field inválido.');
    }
  }

  static String _join(String first, String second) =>
      _joinFileSystemPath(first, second);

  static String _joinFileSystemPath(String first, String second) {
    final separator = Platform.pathSeparator;
    final normalizedFirst = first.endsWith(separator)
        ? first.substring(0, first.length - separator.length)
        : first;
    final normalizedSecond = second.replaceAll(RegExp(r'[\\/]'), separator);
    return '$normalizedFirst$separator${normalizedSecond.replaceFirst(RegExp('^${RegExp.escape(separator)}+'), '')}';
  }

  bool _isWindowsAbsolutePath(String value) =>
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) || value.startsWith(r'\\');
}

class _PortableDocument {
  _PortableDocument({
    required this.lines,
    required this.lineEnding,
    required this.hasFinalLineEnding,
    required this.hasBom,
  });

  final List<String> lines;
  final String lineEnding;
  final bool hasFinalLineEnding;
  final bool hasBom;

  List<PortableSettingsRecord> get records {
    final result = <PortableSettingsRecord>[];
    final sections = <_PortableSection>[];
    for (var index = 0; index < lines.length; index++) {
      final match = RegExp(r'^\[([^\]]+)\]\s*$').firstMatch(lines[index]);
      if (match != null) {
        sections.add(_PortableSection(match.group(1)!, index, lines.length));
      }
    }
    for (var index = 0; index < sections.length - 1; index++) {
      sections[index].end = sections[index + 1].start;
    }
    for (final section in sections) {
      final values = <String, String>{};
      for (var line = section.start + 1; line < section.end; line++) {
        final separator = lines[line].indexOf('=');
        if (separator <= 0) continue;
        final key = lines[line].substring(0, separator).trim();
        var value = lines[line].substring(separator + 1);
        if (value.startsWith('sz:') || value.startsWith('dw:')) {
          value = value.substring(3);
        }
        values[key] = value;
      }
      final name = values['Name'];
      final snpid = values['SNPID'];
      if (name == null ||
          name.trim().isEmpty ||
          snpid == null ||
          snpid.trim().isEmpty) {
        continue;
      }
      if (values['UserRemoved'] == '1') continue;
      result.add(
        PortableSettingsRecord(
          section: section.name,
          name: name,
          snpid: snpid,
          contentPath: values['ContentDir']?.trim().isEmpty == true
              ? null
              : values['ContentDir'],
          visibility: int.tryParse(values['Visibility'] ?? ''),
          userListIndex: int.tryParse(values['UserListIndex'] ?? ''),
          hu: values['HU'],
          jdx: values['JDX'],
          upid: values['UPID'],
          authSystem: values['AuthSystem'],
        ),
      );
    }
    return result;
  }
}

class _PortableSection {
  _PortableSection(this.name, this.start, this.end);

  final String name;
  final int start;
  int end;
}
