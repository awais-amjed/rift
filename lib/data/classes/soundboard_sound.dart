/// One clip on a server's soundboard (`001_schema.sql`, `soundboard_sounds`).
///
/// The bytes are not here and never are: a clip is fetched once by whoever
/// hears it and kept on disk, keyed by [objectPath]. Which is why that path is
/// minted once and never rewritten — the server has no UPDATE grant on it, so
/// a clip cannot be repointed at other bytes behind a cache that already
/// holds the old ones.
class SoundboardSound {
  final String id;
  final String name;

  /// A glyph to find it by in a wall of them, or null. Stored as text and not
  /// validated as an emoji: deciding what counts as one is a job for the thing
  /// with a font.
  final String? emoji;

  /// Object name inside the `soundboard` bucket — `<serverId>/<random>.audio`.
  final String objectPath;

  /// What the uploader said its length was. A claim, not a measurement: the
  /// server cannot decode audio, so this is for the label under the clip and
  /// nothing else. What actually bounds playback is the listener's own ceiling.
  final Duration duration;

  final int bytes;

  /// Who added it, or null once they have left.
  final String? createdBy;

  final DateTime? createdAt;

  const SoundboardSound({
    required this.id,
    required this.name,
    required this.objectPath,
    required this.duration,
    required this.bytes,
    this.emoji,
    this.createdBy,
    this.createdAt,
  });

  factory SoundboardSound.fromJson(Map<String, dynamic> json) {
    return SoundboardSound(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String?,
      objectPath: json['object_path'] as String? ?? '',
      duration: Duration(
        milliseconds: (json['duration_ms'] as num?)?.toInt() ?? 0,
      ),
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'object_path': objectPath,
    'duration_ms': duration.inMilliseconds,
    'bytes': bytes,
    'created_by': createdBy,
    'created_at': createdAt?.toIso8601String(),
  };

  SoundboardSound copyWith({
    String? name,
    String? emoji,
    bool clearEmoji = false,
  }) {
    return SoundboardSound(
      id: id,
      name: name ?? this.name,
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
      objectPath: objectPath,
      duration: duration,
      bytes: bytes,
      createdBy: createdBy,
      createdAt: createdAt,
    );
  }
}
