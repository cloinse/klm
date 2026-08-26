import 'package:kontakt_library_manager/core/models/kontakt_library.dart';

class InventoryAssembler {
  final List<_MutableLibrary> _items = <_MutableLibrary>[];

  void setUserListIndex({required String regKey, required int userListIndex}) {
    final normalizedRegKey = _normalize(regKey);
    for (final item in _items) {
      if ((item.regKey != null &&
              _normalize(item.regKey!) == normalizedRegKey) ||
          _normalize(item.name) == normalizedRegKey) {
        item.userListIndex = userListIndex;
        return;
      }
    }
  }

  void add({
    required String name,
    String? regKey,
    String? snpid,
    String? contentPath,
    String? minimumKontaktVersion,
    int? visibility,
    int? userListIndex,
    bool preferContentPath = false,
    bool preferValues = false,
    required RegistrationSource source,
    List<LibraryIssue> issues = const <LibraryIssue>[],
  }) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final cleanRegKey = _clean(regKey);

    _MutableLibrary? match;
    for (final item in _items) {
      final sameRegKey =
          cleanRegKey != null &&
          item.regKey != null &&
          _normalize(item.regKey!) == _normalize(cleanRegKey);
      final sameName = _normalize(item.name) == _normalize(cleanName);
      final nameMatchesExistingRegKey =
          item.regKey != null &&
          _normalize(item.regKey!) == _normalize(cleanName);
      final regKeyMatchesExistingName =
          cleanRegKey != null &&
          _normalize(item.name) == _normalize(cleanRegKey);
      if (sameRegKey ||
          sameName ||
          nameMatchesExistingRegKey ||
          regKeyMatchesExistingName) {
        match = item;
        break;
      }
    }

    match ??= _MutableLibrary(name: cleanName)..regKey = cleanRegKey;
    if (!_items.contains(match)) _items.add(match);
    final cleanContentPath = _clean(contentPath);
    final cleanSnpid = _clean(snpid);
    final cleanMinimumKontaktVersion = _clean(minimumKontaktVersion);
    if (preferValues) {
      match
        ..name = cleanName
        ..regKey = cleanRegKey ?? match.regKey
        ..snpid = cleanSnpid ?? match.snpid
        ..minimumKontaktVersion =
            cleanMinimumKontaktVersion ?? match.minimumKontaktVersion
        ..visibility = visibility ?? match.visibility
        ..userListIndex = userListIndex ?? match.userListIndex;
    } else {
      match
        ..name = match.name.isEmpty ? cleanName : match.name
        ..regKey ??= cleanRegKey
        ..snpid ??= cleanSnpid
        ..minimumKontaktVersion ??= cleanMinimumKontaktVersion
        ..visibility ??= visibility
        ..userListIndex ??= userListIndex;
    }
    match
      ..sources.add(source)
      ..issues.addAll(issues);
    if (cleanContentPath != null &&
        (preferContentPath || match.contentPath == null)) {
      match.contentPath = cleanContentPath;
    }
  }

  List<KontaktLibrary> build() {
    return _items
        .map((item) {
          final identity = item.regKey ?? item.snpid ?? item.name;
          return KontaktLibrary(
            id: _normalize(identity).replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
            name: item.name,
            regKey: item.regKey,
            snpid: item.snpid,
            contentPath: item.contentPath,
            minimumKontaktVersion: item.minimumKontaktVersion,
            visibility: item.visibility,
            userListIndex: item.userListIndex,
            sources: Set<RegistrationSource>.unmodifiable(item.sources),
            issues: List<LibraryIssue>.unmodifiable(item.issues),
          );
        })
        .toList(growable: false);
  }

  String _normalize(String value) => value.trim().toLowerCase();

  String? _clean(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}

class _MutableLibrary {
  _MutableLibrary({required this.name});

  String name;
  String? regKey;
  String? snpid;
  String? contentPath;
  String? minimumKontaktVersion;
  int? visibility;
  int? userListIndex;
  final Set<RegistrationSource> sources = <RegistrationSource>{};
  final List<LibraryIssue> issues = <LibraryIssue>[];
}
