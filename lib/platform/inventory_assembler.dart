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
    int? userListIndex,
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
      if (sameRegKey || sameName) {
        match = item;
        break;
      }
    }

    match ??= _MutableLibrary(name: cleanName)..regKey = cleanRegKey;
    if (!_items.contains(match)) _items.add(match);
    match
      ..name = match.name.isEmpty ? cleanName : match.name
      ..regKey ??= cleanRegKey
      ..snpid ??= _clean(snpid)?.toUpperCase()
      ..contentPath ??= _clean(contentPath)
      ..minimumKontaktVersion ??= _clean(minimumKontaktVersion)
      ..userListIndex ??= userListIndex
      ..sources.add(source)
      ..issues.addAll(issues);
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
  int? userListIndex;
  final Set<RegistrationSource> sources = <RegistrationSource>{};
  final List<LibraryIssue> issues = <LibraryIssue>[];
}
