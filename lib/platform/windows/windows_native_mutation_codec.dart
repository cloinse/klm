import 'dart:convert';
import 'dart:typed_data';

class WindowsNativeMutationCodec {
  const WindowsNativeMutationCodec._();

  static const maxRequestBytes = 2500000;
  static const maxOperations = 1000;
  static const _absentStringLength = 0xffffffff;
  static const _magic = <int>[0x4b, 0x4c, 0x4d, 0x4e, 0x4d, 0x55, 0x54, 0x31];

  static Uint8List encode(Map<String, Object> request) {
    final rawOperations = request['operations'];
    final isBatch = rawOperations != null;
    final operations = isBatch
        ? _operationList(rawOperations)
        : <Map<String, Object>>[request];
    if (operations.isEmpty || operations.length > maxOperations) {
      throw const FormatException('Invalid native mutation batch size.');
    }

    final output = BytesBuilder(copy: false)..add(_magic);
    _writeUint32(output, 1);
    _writeUint32(output, isBatch ? 1 : 0);
    _writeUint32(output, operations.length);
    for (final operation in operations) {
      final operationName = operation['operation'];
      final operationCode = switch (operationName) {
        'upsert' => 1,
        'relocate' => 2,
        'remove' => 3,
        _ => throw const FormatException('Unknown native mutation operation.'),
      };
      _writeUint32(output, operationCode);
      final visibility = operation['visibility'];
      if (visibility != null && visibility is! int) {
        throw const FormatException('Invalid native mutation visibility.');
      }
      final encodedVisibility = visibility as int? ?? -1;
      if (encodedVisibility < -1 || encodedVisibility > 255) {
        throw const FormatException('Invalid native mutation visibility.');
      }
      _writeInt32(output, encodedVisibility);
      for (final field in const <String>[
        'name',
        'regKey',
        'snpid',
        'contentPath',
        'productHintsXml',
        'hu',
        'jdx',
        'upid',
        'authSystem',
      ]) {
        _writeString(output, operation[field]);
      }
    }

    final bytes = output.takeBytes();
    if (bytes.length > maxRequestBytes) {
      throw const FormatException('The native mutation request is too large.');
    }
    return bytes;
  }

  static List<Map<String, Object>> _operationList(Object value) {
    if (value is! List) {
      throw const FormatException('Invalid native mutation operations.');
    }
    return value
        .map((operation) {
          if (operation is! Map) {
            throw const FormatException('Invalid native mutation operation.');
          }
          return <String, Object>{
            for (final entry in operation.entries)
              if (entry.key is String && entry.value is Object)
                entry.key as String: entry.value as Object,
          };
        })
        .toList(growable: false);
  }

  static void _writeString(BytesBuilder output, Object? value) {
    if (value == null) {
      _writeUint32(output, _absentStringLength);
      return;
    }
    if (value is! String) {
      throw const FormatException('Invalid native mutation string.');
    }
    final bytes = utf8.encode(value);
    _writeUint32(output, bytes.length);
    output.add(bytes);
  }

  static void _writeUint32(BytesBuilder output, int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }

  static void _writeInt32(BytesBuilder output, int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    output.add(data.buffer.asUint8List());
  }
}
