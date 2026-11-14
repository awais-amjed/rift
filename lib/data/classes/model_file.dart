import 'package:equatable/equatable.dart';

/// One file Rift downloads rather than ships: a model's weights, or on a
/// desktop that needs it, the runtime that runs one (`ModelCatalog`).
///
/// The app holds the file's SHA-256, so a downloaded copy is exactly as
/// trusted as the app that asked for it, wherever it was fetched from. A new
/// version of a model is a new entry here, with a new [published] name and a
/// new hash, so it is fetched again; the copy it replaces is swept away later
/// (`ModelRepository.sweep`).
class ModelFile extends Equatable {
  /// Where every file is published: one GitHub release, tagged `models`,
  /// that only ever gains files. An older app keeps finding the version it
  /// pinned there after a newer one is added beside it.
  static const String releaseBase =
      'https://github.com/awais-amjed/rift/releases/download/models/';

  /// What the model is, for logs and the progress the app shows.
  final String id;

  /// Its name in the release, with its version in it (`image_safety.v1.tflite`).
  final String published;

  /// Its exact length in bytes.
  final int size;

  /// Its SHA-256, lower-case hex.
  final String sha256;

  const ModelFile({
    required this.id,
    required this.published,
    required this.size,
    required this.sha256,
  });

  Uri get url => Uri.parse('$releaseBase$published');

  /// Its name on disk: the published name with the start of its hash in it,
  /// so a file under this name has passed this hash, and a model republished
  /// under a reused name by mistake is still fetched again.
  String get localName {
    final dot = published.lastIndexOf('.');
    final tag = sha256.substring(0, 12);
    return dot <= 0
        ? '$published-$tag'
        : '${published.substring(0, dot)}-$tag${published.substring(dot)}';
  }

  @override
  List<Object?> get props => [id, published, size, sha256];
}
