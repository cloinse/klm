import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/publish_github_release.dart' as github_publisher;

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
    final packager = File('tool/package_macos_dmg.sh').readAsStringSync();
    final background = File(
      'tool/create_dmg_background.swift',
    ).readAsStringSync();
    final dmgSettings = File('tool/dmg_settings.py').readAsStringSync();
    final publisher = File(
      'tool/publish_github_release.dart',
    ).readAsStringSync();

    expect(
      codemagic,
      contains('KLM_PACKAGE_NAME="klm-macos-v\${KLM_VERSION}"'),
    );
    expect(codemagic, contains('test "\$KLM_FILE_COUNT" -eq 3'));
    expect(codemagic, contains('- klm-macos-v*.zip'));
    expect(codemagic, isNot(contains('- build/legacy/*.dmg')));
    expect(codemagic, contains('dart run tool/generate_appcast.dart'));
    expect(codemagic, contains('--platform macos'));
    expect(codemagic, isNot(contains('tool/generate_macos_appcast.sh')));
    expect(codemagic, contains('events:\n        - tag'));
    expect(codemagic, contains('tag_patterns:'));
    expect(codemagic, contains('tool/publish_github_release.dart'));
    expect(
      codemagic,
      contains('--asset "\$KLM_OUTPUT_DIRECTORY/\$KLM_PACKAGE_NAME.dmg"'),
    );
    expect(
      codemagic,
      contains(
        '--asset "\$KLM_OUTPUT_DIRECTORY/\$KLM_PACKAGE_NAME.dmg.sha256"',
      ),
    );
    expect(codemagic, isNot(contains('--asset "\$CM_BUILD_DIR/')));
    expect(publisher, contains('GITHUB_TOKEN'));
    expect(publisher, contains('replaceReleaseAssets'));
    expect(publisher, contains('updateRepositoryFile'));
    expect(publisher, contains("title: options.title ?? tag"));
    expect(packager, contains('Print :CFBundleShortVersionString'));
    expect(packager, contains('klm-macos-v\${KLM_VERSION}.dmg'));
    expect(background, contains('let height = 400'));
    expect(dmgSettings, contains('window_rect = ((120, 120), (660, 400))'));
  });

  test("GitHub release notes include the versioned What's new heading", () {
    expect(
      github_publisher.formatGitHubReleaseNotes(
        '0.2.9',
        '- Performance and security improvements.',
      ),
      equals(
        "**What's new in v0.2.9?**\n\n- Performance and security improvements.",
      ),
    );
  });
}
