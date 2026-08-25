import 'dart:convert';
import 'dart:io';

const _githubApiVersion = '2022-11-28';
const _defaultRepository = 'cloinse/klm';

Future<void> main(List<String> arguments) async {
  try {
    final options = _Options.parse(arguments);
    if (options == null) {
      stdout.writeln(_usage);
      return;
    }

    final tag = Platform.environment['CM_TAG']?.trim();
    if (tag == null || tag.isEmpty) {
      stdout.writeln('GitHub publishing skipped: this is not a tag build.');
      return;
    }
    if (tag != 'v${options.version}') {
      throw StateError(
        'Codemagic tag $tag does not match version ${options.version}.',
      );
    }

    final token = Platform.environment['GITHUB_TOKEN']?.trim();
    if (token == null || token.isEmpty) {
      throw StateError('GITHUB_TOKEN is required for tag builds.');
    }
    final repository =
        Platform.environment['GITHUB_REPOSITORY']?.trim().isNotEmpty == true
        ? Platform.environment['GITHUB_REPOSITORY']!.trim()
        : _defaultRepository;
    _validateRepository(repository);

    final notes = await _readOptionalFile(options.releaseNotesPath);
    final appcast = File(options.appcastPath);
    await _validateFiles([appcast]);
    final assets = options.assetPaths.map(File.new).toList();
    await _validateFiles(assets);
    _validateUniqueAssetNames(assets);

    final client = _GitHubClient(token: token, repository: repository);
    try {
      final release = await client.ensureRelease(
        tag: tag,
        title: options.title ?? tag,
        notes: formatGitHubReleaseNotes(options.version, notes),
      );
      await client.replaceReleaseAssets(release.id, assets);
      await client.updateRepositoryFile(
        path: options.repositoryAppcastPath,
        contents: await appcast.readAsBytes(),
        message: 'chore: update ${options.repositoryAppcastPath} for $tag',
      );
      stdout.writeln(
        'Published $tag to https://github.com/$repository/releases/tag/$tag',
      );
      stdout.writeln(
        'Updated $repository/${options.repositoryAppcastPath} on main.',
      );
    } finally {
      client.close();
    }
  } catch (error) {
    stderr.writeln('publish_github_release: $error');
    exitCode = 1;
  }
}

String formatGitHubReleaseNotes(String version, String? notes) {
  final details = notes?.trim().isNotEmpty == true
      ? notes!.trim()
      : '- Performance and security improvements.';
  return "**What's new in v$version?**\n\n$details";
}

const _usage = r'''Usage:
  dart run tool/publish_github_release.dart \
    --version <version> \
    --appcast <generated-appcast.xml> \
    --repository-appcast-path updates/appcast-<platform>.xml \
    --asset <installer> \
    --asset <sha256-file> \
    [--release-notes updates/release-notes.txt] \
    [--title <release-title>]

Required environment variables on tag builds:
  CM_TAG          The tag being built, for example v0.2.8.
  GITHUB_TOKEN    Fine-grained token with Contents: write permission.
  GITHUB_REPOSITORY (optional, defaults to cloinse/klm).

The appcast is committed to the repository path and is not uploaded as a
GitHub Release asset. Release assets are limited to the installer and SHA-256
file supplied with --asset.
''';

class _Options {
  const _Options({
    required this.version,
    required this.appcastPath,
    required this.repositoryAppcastPath,
    required this.assetPaths,
    required this.releaseNotesPath,
    required this.title,
  });

  final String version;
  final String appcastPath;
  final String repositoryAppcastPath;
  final List<String> assetPaths;
  final String? releaseNotesPath;
  final String? title;

  static _Options? parse(List<String> arguments) {
    if (arguments.isEmpty || arguments.contains('--help')) return null;

    String? version;
    String? appcastPath;
    String? repositoryAppcastPath;
    String? releaseNotesPath;
    String? title;
    final assetPaths = <String>[];

    for (var index = 0; index < arguments.length; index += 1) {
      final option = arguments[index];
      if (index + 1 >= arguments.length) {
        throw FormatException('Missing value for $option.');
      }
      final value = arguments[index + 1].trim();
      if (value.isEmpty) throw FormatException('Empty value for $option.');

      switch (option) {
        case '--version':
          if (version != null) {
            throw const FormatException('Duplicate --version.');
          }
          version = value;
        case '--appcast':
          if (appcastPath != null) {
            throw const FormatException('Duplicate --appcast.');
          }
          appcastPath = value;
        case '--repository-appcast-path':
          if (repositoryAppcastPath != null) {
            throw const FormatException('Duplicate --repository-appcast-path.');
          }
          repositoryAppcastPath = value;
        case '--asset':
          assetPaths.add(value);
        case '--release-notes':
          if (releaseNotesPath != null) {
            throw const FormatException('Duplicate --release-notes.');
          }
          releaseNotesPath = value;
        case '--title':
          if (title != null) throw const FormatException('Duplicate --title.');
          title = value;
        default:
          throw FormatException('Unknown option $option.');
      }
      index += 1;
    }

    if (version == null ||
        appcastPath == null ||
        repositoryAppcastPath == null) {
      throw const FormatException(
        '--version, --appcast, and --repository-appcast-path are required.',
      );
    }
    if (assetPaths.length != 2 ||
        assetPaths.where((path) => path.endsWith('.sha256')).length != 1) {
      throw const FormatException(
        'Exactly two --asset values are required: the installer and one .sha256 file.',
      );
    }
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
      throw FormatException('Invalid release version: $version.');
    }
    if (!repositoryAppcastPath.startsWith('updates/appcast-') ||
        !repositoryAppcastPath.endsWith('.xml')) {
      throw const FormatException(
        '--repository-appcast-path must be an updates/appcast-*.xml file.',
      );
    }

    return _Options(
      version: version,
      appcastPath: appcastPath,
      repositoryAppcastPath: repositoryAppcastPath,
      assetPaths: assetPaths,
      releaseNotesPath: releaseNotesPath,
      title: title,
    );
  }
}

Future<String?> _readOptionalFile(String? path) async {
  if (path == null) return null;
  final file = File(path);
  if (!await file.exists()) {
    throw StateError('Release notes not found: ${file.path}');
  }
  final value = (await file.readAsString()).trim();
  if (value.contains(']]>')) {
    throw const FormatException(
      'Release notes cannot contain the CDATA terminator.',
    );
  }
  return value.isEmpty ? null : value;
}

Future<void> _validateFiles(List<File> files) async {
  for (final file in files) {
    if (!await file.exists()) {
      throw StateError('Release asset not found: ${file.path}');
    }
    if (await file.length() == 0) {
      throw StateError('Release asset is empty: ${file.path}');
    }
  }
}

void _validateUniqueAssetNames(List<File> files) {
  final names = <String>{};
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    if (!names.add(name)) {
      throw StateError('Duplicate release asset name: $name');
    }
  }
}

void _validateRepository(String repository) {
  if (!RegExp(r'^[^/]+/[^/]+$').hasMatch(repository)) {
    throw StateError('Invalid GitHub repository: $repository');
  }
}

class _Release {
  const _Release({required this.id});

  final int id;
}

class _ApiResponse {
  const _ApiResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  Object? get json => body.trim().isEmpty ? null : jsonDecode(body);
}

class _GitHubClient {
  _GitHubClient({required this.token, required this.repository});

  final String token;
  final String repository;
  final HttpClient _httpClient = HttpClient();

  void close() => _httpClient.close(force: true);

  Future<_Release> ensureRelease({
    required String tag,
    required String title,
    required String notes,
  }) async {
    final existing = await _request(
      'GET',
      '/releases/tags/${Uri.encodeComponent(tag)}',
    );
    if (existing.statusCode == HttpStatus.ok) {
      final data = _asMap(existing.json, 'GitHub release lookup');
      final id = _asInt(data['id'], 'GitHub release id');
      if (data['draft'] == true) {
        await _requestJson(
          'PATCH',
          '/releases/$id',
          body: {'draft': false, 'name': title},
          expected: {HttpStatus.ok},
        );
      }
      stdout.writeln('Using existing GitHub release $tag.');
      return _Release(id: id);
    }
    if (existing.statusCode != HttpStatus.notFound) {
      _throwApiError('GitHub release lookup', existing);
    }

    final created = await _requestJson(
      'POST',
      '/releases',
      body: {
        'tag_name': tag,
        'name': title,
        'body': notes,
        'draft': false,
        'prerelease': false,
      },
      expected: {HttpStatus.created},
    );
    final data = _asMap(created, 'GitHub release creation');
    final id = _asInt(data['id'], 'GitHub release id');
    stdout.writeln('Created GitHub release $tag.');
    return _Release(id: id);
  }

  Future<void> replaceReleaseAssets(int releaseId, List<File> files) async {
    final existing = await _requestJson(
      'GET',
      '/releases/$releaseId/assets?per_page=100',
      expected: {HttpStatus.ok},
    );
    final existingAssets = _asList(existing, 'GitHub release assets');
    final assetsByName = <String, int>{};
    for (final value in existingAssets) {
      final asset = _asMap(value, 'GitHub release asset');
      final name = asset['name'];
      final id = asset['id'];
      if (name is String && id is int) assetsByName[name] = id;
    }

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final previousId = assetsByName[name];
      if (previousId != null) {
        await _requestJson(
          'DELETE',
          '/releases/assets/$previousId',
          expected: {HttpStatus.noContent},
        );
      }
      await _uploadAsset(releaseId, file, name);
    }
  }

  Future<void> updateRepositoryFile({
    required String path,
    required List<int> contents,
    required String message,
  }) async {
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final current = await _request(
        'GET',
        '/contents/${_encodePath(path)}?ref=main',
      );
      String? sha;
      if (current.statusCode == HttpStatus.ok) {
        final data = _asMap(current.json, 'Repository file lookup');
        sha = data['sha'] as String?;
        final currentContent = data['content'] as String?;
        if (currentContent != null &&
            _sameBytes(_decodeGitHubContent(currentContent), contents)) {
          stdout.writeln('Appcast is already current at $path.');
          return;
        }
      } else if (current.statusCode != HttpStatus.notFound) {
        _throwApiError('Repository file lookup', current);
      }

      final body = <String, Object>{
        'message': message,
        'content': base64Encode(contents),
        'branch': 'main',
      };
      if (sha != null) body['sha'] = sha;
      final updated = await _request(
        'PUT',
        '/contents/${_encodePath(path)}',
        body: body,
      );
      if (updated.statusCode == HttpStatus.ok ||
          updated.statusCode == HttpStatus.created) {
        stdout.writeln('Updated appcast source at $path.');
        return;
      }
      if (updated.statusCode != HttpStatus.conflict || attempt == 1) {
        _throwApiError('Repository file update', updated);
      }
    }
  }

  Future<void> _uploadAsset(int releaseId, File file, String name) async {
    final uri = Uri.https(
      'uploads.github.com',
      '/repos/$repository/releases/$releaseId/assets',
      {'name': name},
    );
    final request = await _httpClient.postUrl(uri);
    _setHeaders(request);
    request.headers.contentType = _contentTypeFor(name);
    final bytes = await file.readAsBytes();
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.created) {
      _throwApiError(
        'GitHub asset upload for $name',
        _ApiResponse(statusCode: response.statusCode, body: body),
      );
    }
    stdout.writeln('Uploaded release asset $name.');
  }

  Future<Object?> _requestJson(
    String method,
    String path, {
    Map<String, Object>? body,
    required Set<int> expected,
  }) async {
    final response = await _request(method, path, body: body);
    if (!expected.contains(response.statusCode)) {
      _throwApiError('$method $path', response);
    }
    return response.json;
  }

  Future<_ApiResponse> _request(
    String method,
    String path, {
    Map<String, Object>? body,
  }) async {
    final request = await _httpClient.openUrl(method, _apiUri(path));
    _setHeaders(request);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    return _ApiResponse(
      statusCode: response.statusCode,
      body: await utf8.decoder.bind(response).join(),
    );
  }

  Uri _apiUri(String path) {
    final separator = path.indexOf('?');
    final pathOnly = separator == -1 ? path : path.substring(0, separator);
    final query = separator == -1
        ? <String, String>{}
        : Uri.splitQueryString(path.substring(separator + 1));
    return Uri.https('api.github.com', '/repos/$repository$pathOnly', query);
  }

  void _setHeaders(HttpClientRequest request) {
    request.headers.set('Accept', 'application/vnd.github+json');
    request.headers.set('Authorization', 'Bearer $token');
    request.headers.set('X-GitHub-Api-Version', _githubApiVersion);
    request.headers.set('User-Agent', 'kontakt-library-manager-codemagic');
  }

  static ContentType _contentTypeFor(String name) {
    if (name.endsWith('.xml')) return ContentType('application', 'xml');
    if (name.endsWith('.txt') || name.endsWith('.sha256')) {
      return ContentType.text;
    }
    if (name.endsWith('.zip')) return ContentType('application', 'zip');
    if (name.endsWith('.dmg')) {
      return ContentType('application', 'x-apple-diskimage');
    }
    if (name.endsWith('.exe')) {
      return ContentType('application', 'octet-stream');
    }
    return ContentType('application', 'octet-stream');
  }
}

Map<String, Object?> _asMap(Object? value, String description) {
  if (value is Map<String, Object?>) return value;
  throw StateError('$description returned an invalid response.');
}

List<Object?> _asList(Object? value, String description) {
  if (value is List<Object?>) return value;
  throw StateError('$description returned an invalid response.');
}

int _asInt(Object? value, String description) {
  if (value is int) return value;
  throw StateError('$description returned an invalid response.');
}

List<int> _decodeGitHubContent(String value) {
  final normalized = value.replaceAll(RegExp(r'\s'), '');
  return base64Decode(normalized);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

String _encodePath(String path) =>
    path.split('/').map(Uri.encodeComponent).join('/');

void _throwApiError(String operation, _ApiResponse response) {
  var detail = response.body.trim();
  if (detail.length > 500) detail = '${detail.substring(0, 500)}...';
  throw StateError(
    '$operation failed with HTTP ${response.statusCode}.'
    '${detail.isEmpty ? '' : ' $detail'}',
  );
}
