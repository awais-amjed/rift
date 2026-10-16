import 'package:equatable/equatable.dart';

/// The call to go back into after Rift restarts itself for an update.
///
/// Written only by Restart to update, never by a quit: someone who quits is
/// done with the call, and Rift also starts at sign-in, hidden in the tray,
/// where joining a call with the mic open would be the last thing anyone
/// expected. A restart for an update is Rift leaving on its own account, so
/// it puts the person back where it found them.
class CallToResume extends Equatable {
  /// How long after the restart the call is still rejoined. An update is in
  /// place and running again within seconds; past this, the update failed
  /// and the person opened Rift by hand, much later, for something else.
  static const keptFor = Duration(minutes: 2);

  /// The voice channel. Its id names the server too: the server is the one
  /// whose channel list holds it, as the call card finds it.
  final String channelId;

  /// Deafened when it left. Not saved anywhere else, and rejoining with
  /// sound on would undo a choice the person made a minute ago.
  final bool deafened;

  final DateTime savedAt;

  const CallToResume({
    required this.channelId,
    required this.savedAt,
    this.deafened = false,
  });

  /// Whether a start at [now] still rejoins. A clock set back reads as
  /// stale, not as fresh forever.
  bool isFreshAt(DateTime now) {
    final age = now.difference(savedAt);
    return !age.isNegative && age <= keptFor;
  }

  factory CallToResume.fromJson(Map<String, dynamic> json) {
    return CallToResume(
      channelId: json['channel_id'] as String,
      savedAt: DateTime.parse(json['saved_at'] as String),
      deafened: json['deafened'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'channel_id': channelId,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'deafened': deafened,
  };

  @override
  List<Object?> get props => [channelId, deafened, savedAt];
}
