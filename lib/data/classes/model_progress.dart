import 'package:equatable/equatable.dart';

import 'model_file.dart';

/// Where one model's download stands.
enum ModelStatus { loading, success, failure }

/// How far a model's download has come, as `ModelRepository` reports it:
/// several times a second while it runs, then once with how it ended.
class ModelProgress extends Equatable {
  final ModelFile file;

  /// Bytes on disk so far, including any kept from an earlier, broken try.
  final int received;
  final ModelStatus status;

  const ModelProgress(this.file, this.received, this.status);

  /// From 0 to 1.
  double get fraction =>
      file.size == 0 ? 1 : (received / file.size).clamp(0, 1).toDouble();

  @override
  List<Object?> get props => [file, received, status];
}
