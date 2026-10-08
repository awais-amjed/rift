import 'package:equatable/equatable.dart';

/// A member being dragged out of a voice channel, on their way to another one.
///
/// Carries where they came from as well as who they are, because the drop
/// target has to know whether the drag ends anywhere new — dropping someone
/// back where they started is the one move that can't do anything.
class VoiceDrag extends Equatable {
  final String userId;
  final String name;

  /// The voice channel they're in right now.
  final String fromChannelId;

  /// Whether this is us. Dragging yourself is just joining a channel, and needs
  /// no permission and no round trip.
  final bool isLocal;

  const VoiceDrag({
    required this.userId,
    required this.name,
    required this.fromChannelId,
    this.isLocal = false,
  });

  @override
  List<Object?> get props => [userId, name, fromChannelId, isLocal];
}
