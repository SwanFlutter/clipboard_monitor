const Set<String> _downloadExtensions = {
  // archives
  'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'tbz2', 'xz', 'txz', 'zst',
  'lz', 'lzma', 'cab', 'z',
  // installers / binaries / images
  'exe', 'msi', 'msix', 'appx', 'dmg', 'pkg', 'deb', 'rpm', 'appimage',
  'flatpak', 'snap', 'apk', 'xapk', 'aab', 'ipa', 'jar', 'bin', 'run', 'iso',
  'img',
  // video
  'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg',
  'ts', '3gp',
  // audio
  'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'opus', 'wma',
  // documents / ebooks
  'pdf', 'epub', 'mobi', 'azw3', 'djvu', 'doc', 'docx', 'xls', 'xlsx', 'ppt',
  'pptx', 'odt', 'ods', 'csv',
  // misc
  'torrent', 'srt', 'psd', 'ttf', 'otf', 'woff2',
};

const Set<String> _contentTypeHints = {
  'application/octet-stream',
  'application/zip',
  'application/x-msdownload',
  'application/pdf',
  'video/',
  'audio/',
};

const Set<String> _downloadQueryKeys = {
  'download', 'dl', 'filename', 'file', 'attachment',
  'response-content-disposition', 'response-content-type', 'content-type',
};

/// Heuristic: `true` if [text] is a single http(s) URL that looks like a
/// direct file download (known file extension in the path or query, or a
/// content-type / content-disposition hint).
bool looksLikeDownloadUrl(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 8192 || RegExp(r'\s').hasMatch(t)) return false;

  final Uri uri;
  try {
    uri = Uri.parse(t);
  } on FormatException {
    return false;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  if (uri.host.isEmpty) return false;

  // 1. File extension in the last path segment (handles ".tar.gz" too).
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && _hasDownloadExtension(segments.last)) return true;

  // 2. Hints in the query string.
  final lowerQuery = Uri.decodeComponent(uri.query).toLowerCase();
  for (final hint in _contentTypeHints) {
    if (lowerQuery.contains(hint)) return true;
  }
  if (lowerQuery.contains('attachment')) return true;
  for (final entry in uri.queryParametersAll.entries) {
    final key = entry.key.toLowerCase();
    for (final value in entry.value) {
      if (_hasDownloadExtension(value)) return true;
      if (!_downloadQueryKeys.contains(key)) continue;
      final isFlag = key == 'dl' || key == 'download';
      // ?dl=1 / ?download / ?download=true are flags; ?filename=... always counts.
      if (!isFlag || value.isEmpty || value == '1' || value == 'true') {
        return true;
      }
    }
  }

  // 3. A "/download/" path segment.
  if (segments.any((s) => s.toLowerCase() == 'download')) return true;

  return false;
}

bool _hasDownloadExtension(String name) {
  final lower = name.toLowerCase();
  final dot = lower.lastIndexOf('.');
  if (dot <= 0 || dot == lower.length - 1) return false;
  return _downloadExtensions.contains(lower.substring(dot + 1));
}
