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

    final products = document.findAllElements('Product').toList();
    if (products.length != 1) {
      throw ProductHintsException(
        'Se esperaba exactamente un producto y se encontraron ${products.length}.',
      );
    }

    final product = products.single;
    final name = _value(product, 'Name');
    final regKey = _value(product, 'RegKey');
    final snpid = _value(product, 'SNPID');
    if (name.isEmpty || regKey.isEmpty || snpid.isEmpty) {
      throw const ProductHintsException(
        'La metadata no contiene Name, RegKey y SNPID válidos.',
      );
    }
    _validateFilenameValue(name, 'Name');
    _validateFilenameValue(regKey, 'RegKey');
    String? minimumVersion;
    final applications = <String>{};
    for (final application in product.findAllElements('Application')) {
      final applicationName = application.innerText.trim().toLowerCase();
      if (applicationName.isNotEmpty) applications.add(applicationName);
      if (applicationName == 'kontakt') {
        minimumVersion = _nullable(application.getAttribute('minVersion'));
      }
    }

    final metadata = ProductMetadata(
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
      applications: Set<String>.unmodifiable(applications),
    );
    final serializedXml = document.toXmlString(pretty: true, indent: '  ');
    return ProductHintsDocument(
      metadata: metadata,
      xml: declaration == null ? serializedXml : '$declaration\n$serializedXml',
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
