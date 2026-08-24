import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kontakt_library_manager/platform/windows/windows_native_mutation_codec.dart';

void main() {
  test('encodes a single native removal with an integrity-safe schema', () {
    final bytes = WindowsNativeMutationCodec.encode(<String, Object>{
      'version': 1,
      'operation': 'remove',
      'name': 'Example Library',
      'regKey': 'Example Library',
    });
    final reader = _Reader(bytes);

    expect(reader.bytes(8), utf8.encode('KLMNMUT1'));
    expect(reader.uint32(), 1);
    expect(reader.uint32(), 0);
    expect(reader.uint32(), 1);
    expect(reader.uint32(), 3);
    expect(reader.int32(), -1);
    expect(reader.string(), 'Example Library');
    expect(reader.string(), 'Example Library');
    for (var index = 0; index < 7; index++) {
      expect(reader.string(), isNull);
    }
    expect(reader.isAtEnd, isTrue);
  });

  test('preserves every field in a native upsert batch', () {
    final bytes = WindowsNativeMutationCodec.encode(<String, Object>{
      'version': 1,
      'operations': <Map<String, Object>>[
        <String, Object>{
          'operation': 'upsert',
          'name': 'Library',
          'regKey': 'Library Key',
          'snpid': 'A01',
          'contentPath': r'D:\Libraries\Library',
          'productHintsXml': '<ProductHints/>',
          'visibility': 3,
          'hu': 'HU value',
          'jdx': 'JDX value',
          'upid': 'UPID value',
          'authSystem': 'RAS3',
        },
      ],
    });
    final reader = _Reader(bytes)..bytes(8);

    expect(reader.uint32(), 1);
    expect(reader.uint32(), 1);
    expect(reader.uint32(), 1);
    expect(reader.uint32(), 1);
    expect(reader.int32(), 3);
    expect(reader.string(), 'Library');
    expect(reader.string(), 'Library Key');
    expect(reader.string(), 'A01');
    expect(reader.string(), r'D:\Libraries\Library');
    expect(reader.string(), '<ProductHints/>');
    expect(reader.string(), 'HU value');
    expect(reader.string(), 'JDX value');
    expect(reader.string(), 'UPID value');
    expect(reader.string(), 'RAS3');
    expect(reader.isAtEnd, isTrue);
  });

  test('rejects malformed or oversized native mutation batches', () {
    expect(
      () => WindowsNativeMutationCodec.encode(<String, Object>{
        'operation': 'unknown',
      }),
      throwsFormatException,
    );
    expect(
      () => WindowsNativeMutationCodec.encode(<String, Object>{
        'operations': List<Map<String, Object>>.generate(
          WindowsNativeMutationCodec.maxOperations + 1,
          (_) => <String, Object>{
            'operation': 'remove',
            'name': 'Library',
            'regKey': 'Library',
          },
        ),
      }),
      throwsFormatException,
    );
  });
}

class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset == _bytes.length;

  List<int> bytes(int length) {
    final result = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return result;
  }

  int uint32() {
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 4,
    ).getUint32(0, Endian.little);
    _offset += 4;
    return value;
  }

  int int32() {
    final value = ByteData.sublistView(
      _bytes,
      _offset,
      _offset + 4,
    ).getInt32(0, Endian.little);
    _offset += 4;
    return value;
  }

  String? string() {
    final length = uint32();
    if (length == 0xffffffff) return null;
    return utf8.decode(bytes(length));
  }
}
