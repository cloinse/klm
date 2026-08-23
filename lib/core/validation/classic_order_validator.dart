import 'package:kontakt_library_manager/core/models/kontakt_library.dart';

class ClassicOrderValidationException implements Exception {
  const ClassicOrderValidationException({
    required this.libraryName,
    required this.reason,
  });

  final String libraryName;
  final String reason;

  @override
  String toString() => '$libraryName: $reason';
}

class ClassicOrderValidator {
  const ClassicOrderValidator();

  void validate(List<KontaktLibrary> libraries) {
    if (libraries.length > 10000) {
      throw const ClassicOrderValidationException(
        libraryName: 'Kontakt',
        reason: 'The classic order contains more than 10,000 libraries.',
      );
    }

    final regKeys = <String>{};
    for (final library in libraries) {
      final regKey = library.regKey ?? library.name;
      if (!_isSafeComponent(regKey)) {
        throw ClassicOrderValidationException(
          libraryName: library.name,
          reason: 'The RegKey contains unsafe characters.',
        );
      }
      if (!_isSafeComponent(library.name)) {
        throw ClassicOrderValidationException(
          libraryName: library.name,
          reason: 'The library name contains unsafe characters.',
        );
      }
      if (!regKeys.add(regKey.trim().toLowerCase())) {
        throw ClassicOrderValidationException(
          libraryName: library.name,
          reason: 'Another library uses the same RegKey.',
        );
      }
    }
  }

  bool _isSafeComponent(String value) =>
      value.isNotEmpty &&
      value.length <= 255 &&
      value != '.' &&
      value != '..' &&
      !value.endsWith('.') &&
      !value.endsWith(' ') &&
      !value.contains('/') &&
      !value.contains('\\') &&
      !value.contains('\u0000') &&
      !value.contains('\n') &&
      !value.contains('\r') &&
      !value.runes.any((rune) => rune < 0x20 || rune == 0x7f);
}
