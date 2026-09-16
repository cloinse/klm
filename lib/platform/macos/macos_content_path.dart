/// Converts Native Instruments ContentDir values to a POSIX path.
///
/// Official installers still write classic Mac HFS paths such as
/// `Macintosh HD:Users:Shared:Library:` alongside POSIX JSON records.
String? posixContentPath(String? raw) {
  final path = raw?.trim();
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('/') && !path.contains(':')) {
    return _stripTrailingSeparators(path, '/');
  }
  if (!path.contains(':')) return path;

  final parts = path.split(':').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  if (parts.first == '/') {
    final rest = parts.skip(1).join('/');
    return rest.isEmpty ? '/' : '/$rest';
  }
  final rest = parts.skip(1).join('/');
  if (rest.isEmpty) return null;
  if (_isBootVolume(parts.first)) return '/$rest';
  return '/Volumes/${parts.first}/$rest';
}

bool _isBootVolume(String volume) {
  final normalized = volume.trim().toLowerCase();
  return normalized == 'macintosh hd' ||
      normalized == 'macintosh hd - data' ||
      normalized == '/';
}

String _stripTrailingSeparators(String path, String separator) {
  if (path == separator) return path;
  var end = path.length;
  while (end > 1 && path.startsWith(separator, end - separator.length)) {
    end -= separator.length;
  }
  return path.substring(0, end);
}
