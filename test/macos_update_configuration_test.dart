import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Sparkle uses an install-only user driver on macOS', () {
    final updateBridge = File(
      'macos/Runner/Native/UpdateBridge.swift',
    ).readAsStringSync();

    expect(updateBridge, contains('InstallOnlyUpdateUserDriver'));
    expect(updateBridge, contains('reply(.install)'));
    expect(updateBridge, isNot(contains('SPUStandardUpdaterController')));
    expect(updateBridge, isNot(contains('reply(.dismiss)')));
    expect(updateBridge, isNot(contains('reply(.skip)')));
    expect(updateBridge, contains('case "installUpdate"'));
    expect(updateBridge, contains('item.displayVersionString'));
  });

  test('macOS About panel uses versioned cloin.se branding', () {
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();

    expect(
      appInfo,
      contains(r'PRODUCT_COPYRIGHT = KLM v$(FLUTTER_BUILD_NAME) cloin.se'),
    );
    expect(appInfo, isNot(contains('Juan Ayala')));
  });

  test('Codemagic packages exactly three macOS release files in one ZIP', () {
    final codemagic = File('codemagic.yaml').readAsStringSync();

    expect(
      codemagic,
      contains('KLM_PACKAGE_NAME="klm-macos-v\${KLM_VERSION}"'),
    );
    expect(codemagic, contains('test "\$KLM_FILE_COUNT" -eq 3'));
    expect(codemagic, contains('- klm-macos-v*.zip'));
    expect(codemagic, isNot(contains('- build/legacy/*.dmg')));
  });
}
