part of 'clip_history_cubit.dart';

class ClipHistoryState extends Equatable {
  /// Newest first.
  final List<StoredClip> clips;

  /// Whether the list has been read: before then, an empty list means
  /// nothing about the disk.
  final bool loaded;

  const ClipHistoryState({this.clips = const [], this.loaded = false});

  @override
  List<Object?> get props => [clips, loaded];
}
