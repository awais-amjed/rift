part of 'voice_listeners_cubit.dart';

/// One bot summoned into a voice channel.
typedef SummonedBot = ({String id, String name});

/// One bot that can hear a voice channel.
typedef ListeningBot = ({String id, String name});

/// What the sidebar knows about bots and voice channels.
///
/// Two lists rather than one because they are two different facts. A listener
/// is somebody outside the room hearing it, which is a warning and is drawn as
/// one. A summon is a bot that was asked in — it publishes and cannot hear —
/// which is furniture, and is here mostly so one that never arrived can still
/// be seen and sent away.
class VoiceBotsState extends Equatable {
  /// The bots that can hear each channel.
  final Map<String, List<ListeningBot>> listeners;

  /// Bots summoned into each channel, with the id needed to dismiss one.
  final Map<String, List<SummonedBot>> summons;

  const VoiceBotsState({this.listeners = const {}, this.summons = const {}});

  @override
  List<Object?> get props => [listeners, summons];
}
