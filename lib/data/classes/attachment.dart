/// What kind of attachment this is, so the UI knows how to render it.
enum AttachmentKind {
  image,
  audio,
  file;

  static AttachmentKind fromMime(String mime) {
    if (mime.startsWith('image/')) return AttachmentKind.image;
    if (mime.startsWith('audio/')) return AttachmentKind.audio;
    return AttachmentKind.file;
  }

  static AttachmentKind fromName(String name) {
    switch (name) {
      case 'image':
        return AttachmentKind.image;
      case 'audio':
        return AttachmentKind.audio;
      default:
        return AttachmentKind.file;
    }
  }
}

/// One E2E-encrypted attachment referenced from inside a message body
/// (ARCHITECTURE.md §4). The file *bytes* live as an opaque, separately
/// AES-256-GCM-encrypted blob in the attachments storage bucket; everything
/// needed to fetch and decrypt them — the storage path, the per-file [keyB64]
/// and [nonceB64], and the metadata (name/mime/size) — travels *inside* the
/// already-encrypted [MessageBody], so a compromised server sees neither the
/// key nor the filename, only ciphertext.
class Attachment {
  /// Stable id within the message (used as a widget key / cache key).
  final String id;
  final AttachmentKind kind;

  /// Original filename (for display + download).
  final String name;
  final String mime;

  /// Plaintext byte length (of the original file, before encryption).
  final int size;

  /// Object path within the attachments bucket, e.g. `<scope>/<uuid>.bin`.
  final String storagePath;

  /// The per-file AES-256-GCM key + nonce, base64. Never sent to the server
  /// except sealed inside the message body.
  final String keyB64;
  final String nonceB64;

  /// Optional media hints so the UI can lay out before the blob is fetched.
  final int? width;
  final int? height;
  final int? durationMs;

  const Attachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.mime,
    required this.size,
    required this.storagePath,
    required this.keyB64,
    required this.nonceB64,
    this.width,
    this.height,
    this.durationMs,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] as String,
      kind: AttachmentKind.fromName(json['kind'] as String? ?? 'file'),
      name: json['name'] as String,
      mime: json['mime'] as String,
      size: json['size'] as int,
      storagePath: json['path'] as String,
      keyB64: json['key'] as String,
      nonceB64: json['nonce'] as String,
      width: json['w'] as int?,
      height: json['h'] as int?,
      durationMs: json['dur'] as int?,
    );
  }

  /// Compact keys — this JSON is encrypted, but small envelopes are still nice.
  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'mime': mime,
        'size': size,
        'path': storagePath,
        'key': keyB64,
        'nonce': nonceB64,
        if (width != null) 'w': width,
        if (height != null) 'h': height,
        if (durationMs != null) 'dur': durationMs,
      };
}
