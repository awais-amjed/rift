import 'package:equatable/equatable.dart';

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
///
/// **Unless the sender chose otherwise.** A big file can go up unencrypted
/// ([isEncrypted] false): the server can then read its bytes, though still
/// not its name, and the message says so with a badge. It has no key and no
/// tag, so it carries a SHA-256 of its bytes instead ([sha256B64]), inside the
/// same sealed body — the server can read the file but cannot change it, and a
/// download that does not match is not shown.
class Attachment extends Equatable {
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

  /// SHA-256 of the bytes, base64, for an attachment sent unencrypted; null
  /// for every encrypted one, whose tag does this job.
  final String? sha256B64;

  /// Set when the file was sealed a chunk at a time, as a big one is: the
  /// plaintext bytes in each chunk (`ChunkedLayout`). [nonceB64] is then the
  /// 7-byte STREAM prefix rather than a whole nonce. Null for a file sealed in
  /// one piece, and for one sent unencrypted.
  ///
  /// A client from before chunking reads such a file as one AES-GCM message,
  /// fails its tag, and shows the rest of the message without it.
  final int? chunkSize;

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
    this.sha256B64,
    this.chunkSize,
    this.width,
    this.height,
    this.durationMs,
  });

  /// Whether the server holds ciphertext ([keyB64] opens it) rather than the
  /// file itself.
  bool get isEncrypted => sha256B64 == null;

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
      // A plain file without its digest cannot be checked, so it gets one that
      // matches nothing, and never opens.
      sha256B64: json['plain'] == true
          ? (json['sha256'] as String? ?? '')
          : null,
      chunkSize: json['chunk'] as int?,
      width: json['w'] as int?,
      height: json['h'] as int?,
      durationMs: json['dur'] as int?,
    );
  }

  /// Compact keys — this JSON is encrypted, but small envelopes are still nice.
  ///
  /// A plain file still writes `key` and `nonce`, empty, because a client from
  /// before plain files reads both as required strings: given empty ones it
  /// fails to open the file and shows the rest of the message, where missing
  /// ones would lose the message.
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'mime': mime,
    'size': size,
    'path': storagePath,
    'key': keyB64,
    'nonce': nonceB64,
    if (sha256B64 != null) ...{'plain': true, 'sha256': sha256B64},
    if (chunkSize != null) 'chunk': chunkSize,
    if (width != null) 'w': width,
    if (height != null) 'h': height,
    if (durationMs != null) 'dur': durationMs,
  };

  @override
  List<Object?> get props => [
    id,
    kind,
    name,
    mime,
    size,
    storagePath,
    keyB64,
    nonceB64,
    sha256B64,
    chunkSize,
    width,
    height,
    durationMs,
  ];
}
