import 'dart:io';

import 'package:flutter/services.dart';

class AppUpdateInfo {
  const AppUpdateInfo({required this.currentVersion, required this.configured});

  final String currentVersion;
  final bool configured;
}

abstract interface class AppUpdatePlatform {
  Future<AppUpdateInfo> getInfo();

  Future<void> checkForUpdates();
}

AppUpdatePlatform createAppUpdatePlatform() {
  if (Platform.isMacOS) return MacOSAppUpdatePlatform();
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
      currentVersion: result?['currentVersion'] as String? ?? '',
      configured: result?['configured'] as bool? ?? false,
    );
  }

  @override
  Future<void> checkForUpdates() =>
      _channel.invokeMethod<void>('checkForUpdates');
}

class UnsupportedAppUpdatePlatform implements AppUpdatePlatform {
  const UnsupportedAppUpdatePlatform();

  @override
  Future<AppUpdateInfo> getInfo() async =>
      const AppUpdateInfo(currentVersion: '', configured: false);

  @override
  Future<void> checkForUpdates() {
    throw UnsupportedError('Application updates are unavailable.');
  }
}
