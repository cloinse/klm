import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.configured,
    this.currentBuild = '',
  });

  final String currentVersion;
  final String currentBuild;
  final bool configured;
}

class AvailableAppUpdate {
  const AvailableAppUpdate({required this.version, this.build = ''});

  final String version;
  final String build;
}

abstract interface class AppUpdatePlatform {
  Future<AppUpdateInfo> getInfo();

  Future<AvailableAppUpdate?> probeForUpdates();

  Future<void> installUpdate();
}

AppUpdatePlatform createAppUpdatePlatform() {
  if (Platform.isMacOS) return MacOSAppUpdatePlatform();
  if (Platform.isWindows) return WindowsAppUpdatePlatform();
  return const UnsupportedAppUpdatePlatform();
}

class MacOSAppUpdatePlatform implements AppUpdatePlatform {
  static const _channel = MethodChannel(
    'com.juanayala.kontaktLibraryManager/updates',
  );

  @override
  Future<AppUpdateInfo> getInfo() async {
    final result = await _channel.invokeMapMethod<String, Object?>('getInfo');
    return AppUpdateInfo(
      currentVersion: visibleAppVersion(result?['currentVersion']),
      currentBuild: result?['currentBuild'] as String? ?? '',
      configured: result?['configured'] as bool? ?? false,
    );
  }

  @override
  Future<void> installUpdate() => _channel.invokeMethod<void>('installUpdate');

  @override
  Future<AvailableAppUpdate?> probeForUpdates() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'probeForUpdates',
    );
    final version = visibleAppVersion(result?['version']);
    if (version.isEmpty) return null;
    return AvailableAppUpdate(
      version: version,
      build: result?['build'] as String? ?? '',
    );
  }
}

class WindowsAppUpdatePlatform implements AppUpdatePlatform {
  static const _channel = MethodChannel(
    'com.juanayala.kontaktLibraryManager/updates',
  );
  static final _feedUri = Uri.https(
    'raw.githubusercontent.com',
    '/cloinse/klm/main/updates/appcast-windows.xml',
  );

  @override
  Future<AppUpdateInfo> getInfo() async {
    final result = await _channel.invokeMapMethod<String, Object?>('getInfo');
    return AppUpdateInfo(
      currentVersion: visibleAppVersion(result?['currentVersion']),
      currentBuild: result?['currentBuild'] as String? ?? '',
      configured: result?['configured'] as bool? ?? false,
    );
  }

  @override
  Future<AvailableAppUpdate?> probeForUpdates() async {
    final info = await getInfo();
    if (!info.configured || info.currentVersion.isEmpty) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(_feedUri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Kontakt Library Manager/${info.currentVersion} (Windows)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final appcast = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 8));
      return windowsAppcastAvailableUpdate(
        appcast,
        currentVersion: info.currentVersion,
        currentBuild: info.currentBuild,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> installUpdate() => _channel.invokeMethod<void>('installUpdate');
}

const _sparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle';

String visibleAppVersion(Object? value) =>
    (value as String? ?? '').trim().split('+').first;

AvailableAppUpdate? windowsAppcastAvailableUpdate(
  String appcast, {
  required String currentVersion,
  required String currentBuild,
}) {
  final document = XmlDocument.parse(appcast);
  final currentBuildNumber = int.tryParse(currentBuild.trim());

  for (final item in document.findAllElements('item')) {
    for (final enclosure in item.findElements('enclosure')) {
      final os = enclosure
          .getAttribute('os', namespace: _sparkleNamespace)
          ?.toLowerCase();
      if (os != null && os != 'windows' && os != 'windows-x64') continue;

      final downloadUrl = Uri.tryParse(enclosure.getAttribute('url') ?? '');
      final signature = enclosure.getAttribute(
        'edSignature',
        namespace: _sparkleNamespace,
      );
      if (downloadUrl?.scheme != 'https' || signature?.isNotEmpty != true) {
        continue;
      }

      final build = item
          .findElements('version', namespace: _sparkleNamespace)
          .firstOrNull
          ?.innerText
          .trim();
      final buildNumber = int.tryParse(build ?? '');
      if (currentBuildNumber != null && buildNumber != null) {
        if (buildNumber > currentBuildNumber) {
          final version = item
              .findElements('shortVersionString', namespace: _sparkleNamespace)
              .firstOrNull
              ?.innerText
              .trim();
          if (version?.isNotEmpty == true) {
            return AvailableAppUpdate(version: version!, build: build ?? '');
          }
        }
        continue;
      }

      final version = item
          .findElements('shortVersionString', namespace: _sparkleNamespace)
          .firstOrNull
          ?.innerText
          .trim();
      if (version != null && _compareVersions(version, currentVersion) > 0) {
        return AvailableAppUpdate(version: version, build: build ?? '');
      }
    }
  }
  return null;
}

int _compareVersions(String left, String right) {
  final leftParts = _numericVersionParts(left);
  final rightParts = _numericVersionParts(right);
  final length = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < length; index += 1) {
    final leftPart = index < leftParts.length ? leftParts[index] : 0;
    final rightPart = index < rightParts.length ? rightParts[index] : 0;
    if (leftPart != rightPart) return leftPart.compareTo(rightPart);
  }
  return 0;
}

List<int> _numericVersionParts(String value) => value
    .split(RegExp(r'[^0-9]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => int.tryParse(part) ?? 0)
    .toList(growable: false);

class UnsupportedAppUpdatePlatform implements AppUpdatePlatform {
  const UnsupportedAppUpdatePlatform();

  @override
  Future<AppUpdateInfo> getInfo() async =>
      const AppUpdateInfo(currentVersion: '', configured: false);

  @override
  Future<AvailableAppUpdate?> probeForUpdates() async => null;

  @override
  Future<void> installUpdate() {
    throw UnsupportedError('Application updates are unavailable.');
  }
}
