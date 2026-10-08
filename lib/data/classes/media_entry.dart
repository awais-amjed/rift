import 'dart:typed_data';

/// Where one picture's fetch has got to.
enum MediaStatus { loading, success, failure }

/// One picture held in a `MediaStore`: its status and, once fetched, its
/// bytes.
///
/// Equal when the status is the same and the bytes are the same object. Bytes
/// are never edited in place — a new picture is a new path — so identity is
/// the right test, and comparing megabytes byte by byte on every emit would
/// not be.
class MediaEntry {
  final MediaStatus status;

  /// Set only when [status] is [MediaStatus.success].
  final Uint8List? bytes;

  const MediaEntry.loading() : status = MediaStatus.loading, bytes = null;

  const MediaEntry.failure() : status = MediaStatus.failure, bytes = null;

  const MediaEntry.success(Uint8List this.bytes) : status = MediaStatus.success;

  @override
  bool operator ==(Object other) =>
      other is MediaEntry &&
      other.status == status &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(status, identityHashCode(bytes));
}
