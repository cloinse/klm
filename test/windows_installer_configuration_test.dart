import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('silent Windows updates relaunch KLM without elevation', () {
    final installer = File(
      'windows/installer/kontakt_library_manager.iss',
    ).readAsStringSync();
    final runEntry = installer
        .split('\n')
        .firstWhere((line) => line.startsWith('Filename: "{app}'));

    expect(runEntry, contains('postinstall'));
    expect(runEntry, contains('runasoriginaluser'));
    expect(runEntry, isNot(contains('skipifsilent')));
  });
}
