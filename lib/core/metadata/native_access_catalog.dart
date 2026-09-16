import 'dart:io';

import 'package:kontakt_library_manager/core/metadata/product_hints_parser.dart';
import 'package:kontakt_library_manager/core/models/kontakt_library.dart';

class NativeAccessCatalog {
  NativeAccessCatalog(this._productsByKey);

  final Map<String, ProductMetadata> _productsByKey;

  static const catalogFileNames = {'nativeaccess.xml', 'native access.xml'};

  static bool isCatalogFileName(String fileName) =>
      catalogFileNames.contains(fileName.toLowerCase());

  factory NativeAccessCatalog.fromProducts(Iterable<ProductMetadata> products) {
    final index = <String, ProductMetadata>{};
    for (final product in products) {
      if (!product.isKontaktLibraryMetadata) continue;
      for (final key in [product.name, product.regKey, product.snpid]) {
        final normalized = key.trim().toLowerCase();
        if (normalized.isNotEmpty) index[normalized] = product;
      }
    }
    return NativeAccessCatalog(index);
  }

  factory NativeAccessCatalog.parse(
    String source, {
    ProductHintsParser parser = const ProductHintsParser(),
  }) {
    return NativeAccessCatalog.fromProducts(parser.parseCatalogText(source));
  }

  static Future<NativeAccessCatalog?> load(
    Directory directory, {
    ProductHintsParser parser = const ProductHintsParser(),
  }) async {
    if (!await directory.exists()) return null;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!isCatalogFileName(_fileName(entity.path))) continue;
      try {
        return NativeAccessCatalog.parse(
          await entity.readAsString(),
          parser: parser,
        );
      } catch (_) {
        return NativeAccessCatalog.fromProducts(const []);
      }
    }
    return null;
  }

  bool get isEmpty => _productsByKey.isEmpty;

  ProductMetadata? find({required String name, String? regKey, String? snpid}) {
    for (final key in [name, regKey, snpid]) {
      if (key == null || key.trim().isEmpty) continue;
      final match = _productsByKey[key.trim().toLowerCase()];
      if (match != null) return match;
    }
    return null;
  }

  List<KontaktLibrary> applyTo(List<KontaktLibrary> libraries) {
    return [for (final library in libraries) _applyToLibrary(library)];
  }

  KontaktLibrary _applyToLibrary(KontaktLibrary library) {
    if (library.hasServiceCenter) return library;
    final match = find(
      name: library.name,
      regKey: library.regKey,
      snpid: library.snpid,
    );
    if (match == null) return library;
    return library.copyWith(
      snpid: library.snpid ?? match.snpid,
      minimumKontaktVersion:
          library.minimumKontaktVersion ?? match.minimumKontaktVersion,
      sources: {...library.sources, RegistrationSource.nativeAccessCatalog},
    );
  }

  static String _fileName(String path) =>
      path.replaceAll('\\', '/').split('/').last;
}

Future<List<KontaktLibrary>> applyNativeAccessCatalogIfNeeded(
  List<KontaktLibrary> libraries,
  Directory serviceCenter, {
  ProductHintsParser parser = const ProductHintsParser(),
}) async {
  if (libraries.every((library) => library.hasServiceCenter)) {
    return libraries;
  }
  final catalog = await NativeAccessCatalog.load(serviceCenter, parser: parser);
  if (catalog == null) return libraries;
  return catalog.applyTo(libraries);
}
