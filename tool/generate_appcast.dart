import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _windowsPublicKey = 'IEM06s9BrwRuC4XtbnRQi6/hVNrTP+aN0naS8RdQNA8=';
const _sparkleNamespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle';
const _sparkleVersion = '2.9.2';
const _sparkleArchiveSha256 =
    '1cb340cbbef04c6c0d162078610c25e2221031d794a3449d89f2f56f4df77c95';

Future<void> main(List<String> arguments) async {
  try {
    final options = _parseOptions(arguments);
    if (options == null) {
      stdout.writeln(_usage);
      return;
    }

    switch (options.platform) {
      case _Platform.windows:
        await _generateWindowsAppcast(options);
      case _Platform.macos:
        await _generateMacosAppcast(options);
    }
  } catch (error) {
    stderr.writeln('generate_appcast: $error');
    exitCode = 1;
  }
}

const _usage = '''Usage:
  Windows (WinSparkle):
    dart run tool/generate_appcast.dart \\
      --platform windows \\
      --installer <installer.exe> \\
      --output <appcast-windows.xml> \\
      --version <version> \\
      --build <build> \\
      --winsparkle-tool <WinSparkleSign.exe> \\
      [--release-notes <release-notes.txt>]

  macOS (Sparkle):
    dart run tool/generate_appcast.dart \\
      --platform macos \\
      --archives-directory <directory-containing-dmgs> \\
      --output <appcast-macos.xml> \\
      [--release-notes <release-notes.txt>]

Required environment variables:
  KLM_UPDATE_DOWNLOAD_URL_PREFIX
  KLM_SPARKLE_PRIVATE_KEY or KLM_SPARKLE_PRIVATE_KEY_FILE

For macOS, KLM_SPARKLE_PRIVATE_KEY_FILE defaults to
.secrets/KLM_SPARKLE_PRIVATE_KEY when neither key variable is set.
KLM_RELEASE_NOTES_PATH can provide release notes when --release-notes is omitted.
''';

enum _Platform { windows, macos }

class _Options {
  const _Options({
    required this.platform,
    required this.outputPath,
    required this.releaseNotesPath,
    this.installerPath,
    this.version,
    this.build,
    this.winSparkleTool,
    this.archivesDirectory,
  });

  final _Platform platform;
  final String outputPath;
  final String? releaseNotesPath;
  final String? installerPath;
  final String? version;
  final String? build;
  final String? winSparkleTool;
  final String? archivesDirectory;
}

_Options? _parseOptions(List<String> arguments) {
  if (arguments.isEmpty || arguments.contains('--help')) return null;

  const allowed = <String>{
    '--platform',
    '--installer',
    '--output',
    '--version',
    '--build',
    '--winsparkle-tool',
    '--archives-directory',
    '--release-notes',
  };
  final values = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length || !allowed.contains(arguments[index])) {
      throw const FormatException('Invalid arguments. Use --help for usage.');
    }
    final name = arguments[index];
    final value = arguments[index + 1].trim();
    if (value.isEmpty || values.containsKey(name)) {
      throw const FormatException('Each option must have one non-empty value.');
    }
    values[name] = value;
  }

  String required(String name) =>
      values[name] ??
      (throw FormatException('Missing required option $name. Use --help.'));

  final platformName = required('--platform').toLowerCase();
  final platform = switch (platformName) {
    'windows' => _Platform.windows,
    'macos' => _Platform.macos,
    _ => throw const FormatException(
      'Platform must be either windows or macos. Use --help for usage.',
    ),
  };

  final releaseNotesValue =
      values['--release-notes'] ??
      Platform.environment['KLM_RELEASE_NOTES_PATH'];
  final releaseNotesPath = releaseNotesValue == null
      ? null
      : releaseNotesValue.trim().isEmpty
      ? null
      : releaseNotesValue.trim();
  final outputPath = required('--output');
  if (platform == _Platform.windows) {
    return _Options(
      platform: platform,
      outputPath: outputPath,
      releaseNotesPath: releaseNotesPath,
      installerPath: required('--installer'),
      version: required('--version'),
      build: required('--build'),
      winSparkleTool: required('--winsparkle-tool'),
    );
  }

  return _Options(
    platform: platform,
    outputPath: outputPath,
    releaseNotesPath: releaseNotesPath,
    archivesDirectory: required('--archives-directory'),
  );
}

Future<void> _generateWindowsAppcast(_Options options) async {
  final downloadUrlPrefix = _requiredDownloadUrlPrefix();
  final installer = File(options.installerPath!);
  if (!await installer.exists()) {
    throw StateError('Installer not found: ${installer.path}');
  }
  final signingTool = File(options.winSparkleTool!);
  if (!await signingTool.exists()) {
    throw StateError('WinSparkle signing tool not found: ${signingTool.path}');
  }

  final releaseNotes = await _readReleaseNotes(options.releaseNotesPath);
  final privateKey = await _loadPrivateKey(allowDefaultFile: false);
  try {
    final signature = await _signInstaller(
      signingTool.path,
      privateKey.path!,
      installer.path,
    );
    await _verifyInstaller(signingTool.path, signature, installer.path);

    final output = File(options.outputPath);
    await output.parent.create(recursive: true);
    final installerName = installer.uri.pathSegments.last;
    final downloadUrl = '$downloadUrlPrefix$installerName';
    final xml = _appcastXml(
      version: options.version!,
      build: options.build!,
      downloadUrl: downloadUrl,
      installerLength: await installer.length(),
      signature: signature,
      releaseNotes: releaseNotes,
    );
    await output.writeAsBytes(utf8.encode(xml), flush: true);
    stdout.writeln('Created signed Windows appcast: ${output.path}');
  } finally {
    await privateKey.dispose();
  }
}

Future<void> _generateMacosAppcast(_Options options) async {
  final downloadUrlPrefix = _requiredDownloadUrlPrefix();
  final archives = Directory(options.archivesDirectory!);
  if (!await archives.exists()) {
    throw StateError('Archives directory not found: ${archives.path}');
  }

  final releaseNotes = await _readReleaseNotes(options.releaseNotesPath);
  final output = File(options.outputPath);
  await output.parent.create(recursive: true);
  final privateKey = await _loadPrivateKey(allowDefaultFile: true);
  final sparkleRoot = await Directory.systemTemp.createTemp(
    'klm-sparkle-tools-',
  );

  try {
    final archive = File(
      '${sparkleRoot.path}${Platform.pathSeparator}Sparkle-$_sparkleVersion.tar.xz',
    );
    final archiveUrl =
        'https://github.com/sparkle-project/Sparkle/releases/download/'
        '$_sparkleVersion/Sparkle-$_sparkleVersion.tar.xz';
    await _downloadFile(archiveUrl, archive);
    final downloadedSha256 = sha256
        .convert(await archive.readAsBytes())
        .toString();
    if (downloadedSha256 != _sparkleArchiveSha256) {
      throw StateError(
        'Sparkle archive checksum mismatch: expected $_sparkleArchiveSha256, '
        'got $downloadedSha256',
      );
    }

    await _extractSparkleArchive(archive, sparkleRoot);
    final generateAppcast = File(
      '${sparkleRoot.path}${Platform.pathSeparator}bin${Platform.pathSeparator}generate_appcast',
    );
    final signUpdate = File(
      '${sparkleRoot.path}${Platform.pathSeparator}bin${Platform.pathSeparator}sign_update',
    );
    if (!await generateAppcast.exists() || !await signUpdate.exists()) {
      throw StateError(
        'Sparkle tools are missing from the downloaded archive.',
      );
    }

    await _runWithPrivateKey(
      generateAppcast.path,
      [
        '--ed-key-file',
        '-',
        '--download-url-prefix',
        downloadUrlPrefix,
        '--maximum-deltas',
        '0',
        '-o',
        output.path,
        archives.path,
      ],
      privateKey.contents,
      description: 'Sparkle appcast generation',
    );
    await _embedMacosReleaseNotes(output, releaseNotes);
    await _runWithPrivateKey(
      signUpdate.path,
      ['--ed-key-file', '-', output.path],
      privateKey.contents,
      description: 'Sparkle appcast signing',
    );
    await _runWithPrivateKey(
      signUpdate.path,
      ['--verify', '--ed-key-file', '-', output.path],
      privateKey.contents,
      description: 'Sparkle appcast verification',
    );
    stdout.writeln('Created signed macOS appcast: ${output.path}');
  } finally {
    await privateKey.dispose();
    if (await sparkleRoot.exists()) {
      await sparkleRoot.delete(recursive: true);
    }
  }
}

String _requiredDownloadUrlPrefix() {
  final value = Platform.environment['KLM_UPDATE_DOWNLOAD_URL_PREFIX']?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('Set KLM_UPDATE_DOWNLOAD_URL_PREFIX.');
  }
  return '${value.replaceFirst(RegExp(r'/+$'), '')}/';
}

Future<String?> _readReleaseNotes(String? path) async {
  if (path == null) return null;
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('Release notes not found: ${file.path}');
  }
  final releaseNotes = (await file.readAsString()).trim();
  if (releaseNotes.contains(']]>')) {
    throw const FormatException(
      'Release notes cannot contain the CDATA terminator.',
    );
  }
  return releaseNotes.isEmpty ? null : releaseNotes;
}

class _PrivateKey {
  const _PrivateKey({
    required this.contents,
    this.path,
    this.temporaryDirectory,
  });

  final String contents;
  final String? path;
  final Directory? temporaryDirectory;

  Future<void> dispose() async {
    if (temporaryDirectory != null && await temporaryDirectory!.exists()) {
      await temporaryDirectory!.delete(recursive: true);
    }
  }
}

Future<_PrivateKey> _loadPrivateKey({required bool allowDefaultFile}) async {
  final inlineKey = Platform.environment['KLM_SPARKLE_PRIVATE_KEY'];
  if (inlineKey != null && inlineKey.trim().isNotEmpty) {
    final directory = await Directory.systemTemp.createTemp('klm-sparkle-key-');
    final keyFile = File(
      '${directory.path}${Platform.pathSeparator}private-key',
    );
    await keyFile.writeAsString(inlineKey, encoding: utf8, flush: true);
    return _PrivateKey(
      contents: inlineKey,
      path: keyFile.path,
      temporaryDirectory: directory,
    );
  }

  var configuredPath = Platform.environment['KLM_SPARKLE_PRIVATE_KEY_FILE']
      ?.trim();
  if ((configuredPath == null || configuredPath.isEmpty) && allowDefaultFile) {
    configuredPath = '.secrets/KLM_SPARKLE_PRIVATE_KEY';
  }
  if (configuredPath == null || configuredPath.isEmpty) {
    throw StateError(
      'Configure KLM_SPARKLE_PRIVATE_KEY or KLM_SPARKLE_PRIVATE_KEY_FILE.',
    );
  }
  final keyFile = File(configuredPath);
  if (!await keyFile.exists()) {
    throw StateError('Private key not found: ${keyFile.path}');
  }
  final contents = await keyFile.readAsString();
  if (contents.trim().isEmpty) {
    throw StateError('Private key is empty: ${keyFile.path}');
  }
  return _PrivateKey(contents: contents, path: keyFile.path);
}

Future<String> _signInstaller(
  String signingTool,
  String privateKeyPath,
  String installerPath,
) async {
  final result = await Process.run(signingTool, [
    'sign',
    '--private-key-file',
    privateKeyPath,
    installerPath,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'WinSparkle could not sign the installer: ${result.stderr}',
    );
  }
  final signature = (result.stdout as String).trim();
  try {
    if (base64Decode(signature).length != 64) {
      throw const FormatException();
    }
  } on FormatException {
    throw const FormatException('Invalid EdDSA signature.');
  }
  return signature;
}

Future<void> _verifyInstaller(
  String signingTool,
  String signature,
  String installerPath,
) async {
  final result = await Process.run(signingTool, [
    'verify',
    '--public-key',
    _windowsPublicKey,
    '--signature',
    signature,
    installerPath,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Installer signature verification failed: ${result.stderr}',
    );
  }
}

Future<void> _downloadFile(String url, File destination) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.followRedirects = true;
    request.maxRedirects = 8;
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Could not download $url (HTTP ${response.statusCode}).',
      );
    }
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    await destination.writeAsBytes(bytes, flush: true);
  } finally {
    client.close(force: true);
  }
}

Future<void> _extractSparkleArchive(File archive, Directory destination) async {
  final result = await Process.run('/usr/bin/tar', [
    '-xf',
    archive.path,
    '-C',
    destination.path,
  ]);
  if (result.exitCode != 0) {
    throw StateError('Could not extract Sparkle: ${result.stderr}');
  }
}

Future<void> _runWithPrivateKey(
  String executable,
  List<String> arguments,
  String privateKey, {
  required String description,
}) async {
  final process = await Process.start(executable, arguments);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(privateKey);
  await process.stdin.close();
  final exitCode = await process.exitCode;
  final stdoutText = await stdoutFuture;
  final stderrText = await stderrFuture;
  if (exitCode != 0) {
    final detail = stderrText.trim().isEmpty
        ? stdoutText.trim()
        : stderrText.trim();
    throw StateError('$description failed${detail.isEmpty ? '' : ': $detail'}');
  }
}

Future<void> _embedMacosReleaseNotes(File output, String? releaseNotes) async {
  if (releaseNotes == null) return;
  final appcast = await output.readAsString();
  final enclosure = RegExp(r'<enclosure(?:\s|>)').firstMatch(appcast);
  if (enclosure == null) {
    throw StateError('Sparkle appcast does not contain an enclosure.');
  }
  final description =
      '      <description sparkle:format="plain-text"><![CDATA[\n'
      '$releaseNotes\n'
      ']]></description>\n';
  final updated = appcast.replaceRange(
    enclosure.start,
    enclosure.start,
    description,
  );
  await output.writeAsString(updated, encoding: utf8, flush: true);
}

String _appcastXml({
  required String version,
  required String build,
  required String downloadUrl,
  required int installerLength,
  required String signature,
  required String? releaseNotes,
}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln('<rss version="2.0" xmlns:sparkle="$_sparkleNamespace">')
    ..writeln('  <channel>')
    ..writeln('    <title>Kontakt Library Manager - Windows</title>')
    ..writeln('    <item>')
    ..writeln('      <title>${_xmlEscape(version)}</title>')
    ..writeln(
      '      <pubDate>${_xmlEscape(HttpDate.format(DateTime.now().toUtc()))}</pubDate>',
    )
    ..writeln('      <sparkle:version>${_xmlEscape(build)}</sparkle:version>')
    ..writeln(
      '      <sparkle:shortVersionString>${_xmlEscape(version)}</sparkle:shortVersionString>',
    )
    ..writeln(
      '      <sparkle:minimumSystemVersion>10.0</sparkle:minimumSystemVersion>',
    );
  if (releaseNotes != null) {
    buffer.writeln(
      '      <description sparkle:format="plain-text"><![CDATA[$releaseNotes]]></description>',
    );
  }
  buffer
    ..writeln('      <enclosure')
    ..writeln('        url="${_xmlEscape(downloadUrl)}"')
    ..writeln('        length="$installerLength"')
    ..writeln('        type="application/octet-stream"')
    ..writeln('        sparkle:os="windows-x64"')
    ..writeln(
      '        sparkle:installerArguments="/SILENT /SP- /NOICONS /NORESTART"',
    )
    ..writeln('        sparkle:edSignature="${_xmlEscape(signature)}"')
    ..writeln('      />')
    ..writeln('    </item>')
    ..writeln('  </channel>')
    ..writeln('</rss>');
  return buffer.toString();
}

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
