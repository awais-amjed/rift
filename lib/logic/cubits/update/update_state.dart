part of 'update_cubit.dart';

enum UpdateStatus {
  /// This copy cannot update itself (see [UpdateRepository]).
  unsupported,

  /// Nothing asked yet, or nothing newer the last time.
  upToDate,
  checking,
  downloading,

  /// Downloaded, and put in place by a restart.
  ready,

  /// Handed to the updater; Rift is quitting.
  restarting,
  failed,
}

class UpdateState extends Equatable {
  final UpdateStatus status;

  /// The version this copy was installed as; null when [UpdateStatus.unsupported].
  final String? installedVersion;

  /// The release being downloaded or ready to restart into.
  final String? version;

  /// Its notes, as the release tag's message has them.
  final String notes;

  /// How far the download is, 0 to 100.
  final int progress;

  /// Why the last check or download failed.
  final String? error;

  const UpdateState({
    required this.status,
    this.installedVersion,
    this.version,
    this.notes = '',
    this.progress = 0,
    this.error,
  });

  bool get canUpdate => status != UpdateStatus.unsupported;

  /// Busy with something that a second check would only get in the way of.
  bool get busy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.ready ||
      status == UpdateStatus.restarting;

  UpdateState copyWith({
    UpdateStatus? status,
    String? version,
    String? notes,
    int? progress,
    String? error,
    bool clearError = false,
  }) {
    return UpdateState(
      status: status ?? this.status,
      installedVersion: installedVersion,
      version: version ?? this.version,
      notes: notes ?? this.notes,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    status,
    installedVersion,
    version,
    notes,
    progress,
    error,
  ];
}
