part of 'media_cubit.dart';

/// Every picture held, by storage path, per [MediaKind].
///
/// Widgets select one entry each, so a picture landing rebuilds only the
/// widgets showing it.
class MediaState {
  final Map<String, MediaEntry> images;
  final Map<String, MediaEntry> attachments;

  const MediaState({this.images = const {}, this.attachments = const {}});

  MediaEntry? entry(MediaKind kind, String path) =>
      (kind == MediaKind.image ? images : attachments)[path];

  /// [path]'s bytes, once fetched.
  Uint8List? bytes(MediaKind kind, String path) => entry(kind, path)?.bytes;

  MediaState copyWith({
    Map<String, MediaEntry>? images,
    Map<String, MediaEntry>? attachments,
  }) => MediaState(
    images: images ?? this.images,
    attachments: attachments ?? this.attachments,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaState &&
      mapEquals(other.images, images) &&
      mapEquals(other.attachments, attachments);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(
      images.entries.map((e) => Object.hash(e.key, e.value)),
    ),
    Object.hashAllUnordered(
      attachments.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
