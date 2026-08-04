import 'dart:io';

enum RegistrationSource {
  serviceCenter,
  preferences,
  installedProducts,
  windowsRegistry,
}

enum IssueSeverity { information, warning, error }

enum LibraryHealth { healthy, warning, error }

class LibraryIssue {
  const LibraryIssue({
    required this.code,
    required this.message,
    required this.severity,
  });

  final String code;
  final String message;
  final IssueSeverity severity;

  @override
  bool operator ==(Object other) =>
      other is LibraryIssue &&
      other.code == code &&
      other.message == message &&
      other.severity == severity;

  @override
  int get hashCode => Object.hash(code, message, severity);
}

class KontaktLibrary {
  const KontaktLibrary({
    required this.id,
    required this.name,
    this.regKey,
    this.snpid,
    this.contentPath,
    this.minimumKontaktVersion,
    this.userListIndex,
    this.sources = const <RegistrationSource>{},
    this.issues = const <LibraryIssue>[],
  });

  final String id;
  final String name;
  final String? regKey;
  final String? snpid;
  final String? contentPath;
  final String? minimumKontaktVersion;
  final int? userListIndex;
  final Set<RegistrationSource> sources;
  final List<LibraryIssue> issues;

  bool get hasServiceCenter =>
      sources.contains(RegistrationSource.serviceCenter);

  bool get hasLegacyRegistration =>
      sources.contains(RegistrationSource.preferences) ||
      sources.contains(RegistrationSource.windowsRegistry);

  bool get hasInstalledProduct =>
      sources.contains(RegistrationSource.installedProducts);

  bool get supportsKontakt6 {
    final version = minimumKontaktVersion;
    if (version == null || version.isEmpty) return true;
    final major = int.tryParse(version.split('.').first);
    return major == null || major <= 6;
  }

  bool get registeredForKontakt6 =>
      hasServiceCenter && hasLegacyRegistration && supportsKontakt6;

  bool get registeredForKontakt78 => hasInstalledProduct;

  bool get contentPathExists {
    final path = contentPath;
    return path != null && path.isNotEmpty && Directory(path).existsSync();
  }

  LibraryHealth get health {
    if (issues.any((issue) => issue.severity == IssueSeverity.error)) {
      return LibraryHealth.error;
    }
    if (issues.any((issue) => issue.severity == IssueSeverity.warning)) {
      return LibraryHealth.warning;
    }
    return LibraryHealth.healthy;
  }

  KontaktLibrary copyWith({
    String? id,
    String? name,
    String? regKey,
    String? snpid,
    String? contentPath,
    String? minimumKontaktVersion,
    int? userListIndex,
    Set<RegistrationSource>? sources,
    List<LibraryIssue>? issues,
  }) {
    return KontaktLibrary(
      id: id ?? this.id,
      name: name ?? this.name,
      regKey: regKey ?? this.regKey,
      snpid: snpid ?? this.snpid,
      contentPath: contentPath ?? this.contentPath,
      minimumKontaktVersion:
          minimumKontaktVersion ?? this.minimumKontaktVersion,
      userListIndex: userListIndex ?? this.userListIndex,
      sources: sources ?? this.sources,
      issues: issues ?? this.issues,
    );
  }
}

class ProductMetadata {
  const ProductMetadata({
    required this.name,
    required this.regKey,
    required this.snpid,
    this.visibility,
    this.hu,
    this.jdx,
    this.upid,
    this.authSystem,
    this.minimumKontaktVersion,
  });

  final String name;
  final String regKey;
  final String snpid;
  final int? visibility;
  final String? hu;
  final String? jdx;
  final String? upid;
  final String? authSystem;
  final String? minimumKontaktVersion;
}
