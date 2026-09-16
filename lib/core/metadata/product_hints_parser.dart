import 'dart:convert';
import 'dart:typed_data';

import 'package:kontakt_library_manager/core/models/kontakt_library.dart';
import 'package:xml/xml.dart';

class ProductHintsException implements Exception {
  const ProductHintsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProductHintsParser {
  const ProductHintsParser();

  ProductMetadata parseBytes(Uint8List bytes) {
    return parseDocumentBytes(bytes).metadata;
  }

  ProductMetadata parseText(String source) {
    return parseDocumentText(source).metadata;
  }

  ProductHintsDocument parseDocumentBytes(Uint8List bytes) {
    return parseDocumentText(utf8.decode(bytes, allowMalformed: true));
  }

  ProductHintsDocument parseDocumentText(String source) {
    final extracted = _extractProductHints(source);
    final products = extracted.document.findAllElements('Product').toList();
    if (products.length != 1) {
      throw ProductHintsException(
        'Se esperaba exactamente un producto y se encontraron ${products.length}.',
      );
    }

    final metadata = _metadataFromProduct(products.single, strict: true);
    if (metadata == null) {
      throw const ProductHintsException(
        'La metadata no contiene Name, RegKey y SNPID válidos.',
      );
    }
    // Keep the original ProductHints bytes intact. Reformatting can drop
    // attributes, ordering, or whitespace that Kontakt uses when resolving
    // library files from Service Center XML.
    return ProductHintsDocument(
      metadata: metadata,
      xml: extracted.declaration == null
          ? extracted.fragment
          : '${extracted.declaration}\n${extracted.fragment}',
    );
  }

  List<ProductMetadata> parseCatalogText(String source) {
    final extracted = _extractProductHints(source);
    final products = <ProductMetadata>[];
    for (final product in extracted.document.findAllElements('Product')) {
      final metadata = _metadataFromProduct(product, strict: false);
      if (metadata == null) continue;
      products.add(metadata);
    }
    return products;
  }

  List<ProductMetadata> parseCatalogBytes(Uint8List bytes) {
    return parseCatalogText(utf8.decode(bytes, allowMalformed: true));
  }

  _ExtractedProductHints _extractProductHints(String source) {
    final start = source.indexOf('<ProductHints');
    final endMarker = '</ProductHints>';
    final end = source.indexOf(endMarker, start < 0 ? 0 : start);
    if (start < 0 || end < 0) {
      throw const ProductHintsException('No se encontró ProductHints.');
    }

    final fragment = source
        .substring(start, end + endMarker.length)
        .replaceAll('\u0000', '');
    final declaration = RegExp(
      r'''<\?xml[^>]*\?>''',
    ).firstMatch(source.substring(0, start))?.group(0);

    late final XmlDocument document;
    try {
      document = XmlDocument.parse(fragment);
    } on XmlParserException catch (error) {
      throw ProductHintsException('ProductHints contiene XML inválido: $error');
    }
    return _ExtractedProductHints(
      document: document,
      fragment: fragment,
      declaration: declaration,
    );
  }

  ProductMetadata? _metadataFromProduct(
    XmlElement product, {
    required bool strict,
  }) {
    final name = _value(product, 'Name');
    final regKey = _value(product, 'RegKey');
    final snpid = _value(product, 'SNPID');
    if (name.isEmpty || regKey.isEmpty || snpid.isEmpty) {
      if (strict) {
        throw const ProductHintsException(
          'La metadata no contiene Name, RegKey y SNPID válidos.',
        );
      }
      return null;
    }
    try {
      _validateFilenameValue(name, 'Name');
      _validateFilenameValue(regKey, 'RegKey');
    } on ProductHintsException {
      if (strict) rethrow;
      return null;
    }
    String? minimumVersion;
    final applications = <String>{};
    for (final application in product.findAllElements('Application')) {
      final applicationName = application.innerText.trim().toLowerCase();
      if (applicationName.isNotEmpty) applications.add(applicationName);
      if (applicationName == 'kontakt') {
        minimumVersion = _nullable(application.getAttribute('minVersion'));
      }
    }

    return ProductMetadata(
      name: name,
      regKey: regKey,
      snpid: snpid,
      visibility: int.tryParse(_productSpecificValue(product, 'Visibility')),
      hu: _nullable(_value(product, 'HU')),
      jdx: _nullable(_value(product, 'JDX')),
      upid: _nullable(_value(product, 'UPID')),
      authSystem: _nullable(_value(product, 'AuthSystem')),
      minimumKontaktVersion: minimumVersion,
      productType: _nullable(_value(product, 'Type')),
      company: _nullable(_value(product, 'Company')),
      poweredBy: _nullable(_value(product, 'PoweredBy')),
      icon: _nullable(_value(product, 'Icon')),
      applications: Set<String>.unmodifiable(applications),
    );
  }

  String _value(XmlElement parent, String name) {
    final elements = parent.findAllElements(name);
    return elements.isEmpty ? '' : elements.first.innerText.trim();
  }

  String _productSpecificValue(XmlElement product, String name) {
    for (final element in product.childElements) {
      if (element.name.local != 'ProductSpecific') continue;
      for (final value in element.childElements) {
        if (value.name.local == name) return value.innerText.trim();
      }
    }
    return '';
  }

  String? _nullable(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  void _validateFilenameValue(String value, String field) {
    if (value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains('\\') ||
        value.contains('\n') ||
        value.contains('\r')) {
      throw ProductHintsException(
        '$field contiene caracteres de ruta no seguros.',
      );
    }
  }
}

class ProductHintsDocument {
  const ProductHintsDocument({required this.metadata, required this.xml});

  final ProductMetadata metadata;
  final String xml;
}

class _ExtractedProductHints {
  const _ExtractedProductHints({
    required this.document,
    required this.fragment,
    required this.declaration,
  });

  final XmlDocument document;
  final String fragment;
  final String? declaration;
}
