/// Minimal filename → MIME mapping. Desktop file pickers frequently leave
/// `XFile.mimeType` null (especially on Linux), so we infer from the extension
/// for the common cases and fall back to a generic binary type.
String mimeFromName(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return _fallback;
  final ext = name.substring(dot + 1).toLowerCase();
  return _byExt[ext] ?? _fallback;
}

const String _fallback = 'application/octet-stream';

const Map<String, String> _byExt = {
  // images
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'bmp': 'image/bmp',
  'svg': 'image/svg+xml',
  'heic': 'image/heic',
  // audio
  'mp3': 'audio/mpeg',
  'm4a': 'audio/mp4',
  'aac': 'audio/aac',
  'wav': 'audio/wav',
  'ogg': 'audio/ogg',
  'opus': 'audio/opus',
  'flac': 'audio/flac',
  // video (rendered as generic files for now)
  'mp4': 'video/mp4',
  'webm': 'video/webm',
  'mov': 'video/quicktime',
  // docs / misc
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'md': 'text/markdown',
  'json': 'application/json',
  'zip': 'application/zip',
  'csv': 'text/csv',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
};
