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

  test('WinSparkle installs only after the shared confirmation dialog', () {
    final updateBridge = File(
      'windows/runner/update_bridge.cpp',
    ).readAsStringSync();

    expect(
      updateBridge,
      contains('win_sparkle_check_update_with_ui_and_install'),
    );
    expect(updateBridge, contains('call.method_name() == "installUpdate"'));
    expect(updateBridge, isNot(contains('"win_sparkle_check_update_with_ui"')));
  });

  test('Windows metadata and updater use cloin.se branding', () {
    final installer = File(
      'windows/installer/kontakt_library_manager.iss',
    ).readAsStringSync();
    final resources = File('windows/runner/Runner.rc').readAsStringSync();
    final updateBridge = File(
      'windows/runner/update_bridge.cpp',
    ).readAsStringSync();

    expect(installer, contains('AppPublisher=cloin.se'));
    expect(installer, contains('VersionInfoCompany=cloin.se'));
    expect(
      installer,
      contains('VersionInfoCopyright=KLM v{#MyAppVersion} cloin.se'),
    );
    expect(resources, contains('VALUE "CompanyName", "cloin.se"'));
    expect(
      resources,
      contains('VALUE "LegalCopyright", "KLM v" VERSION_AS_STRING " cloin.se'),
    );
    expect(
      updateBridge,
      contains('set_app_details(L"cloin.se", L"Kontakt Library Manager"'),
    );
  });

  test('Codemagic does not configure Windows builds', () {
    final codemagic = File('codemagic.yaml').readAsStringSync();

    expect(codemagic, isNot(contains('windows-release:')));
    expect(codemagic, isNot(contains('flutter build windows')));
    expect(codemagic, isNot(contains('klm-windows-v')));
    expect(codemagic, isNot(contains('Inno Setup')));
  });
}
