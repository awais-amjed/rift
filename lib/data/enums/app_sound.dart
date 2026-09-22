import '../classes/participant_setting.dart';

/// The sounds Rift plays on this device. The call's come in the pairs a
/// person thinks of them in — nobody wants the join tone and not the leave
/// tone — and a new message is the one that stands alone.
///
/// Each is muted and turned down as one, in `AppState.appSounds` under
/// its [name]. A volume there is a share of `SoundService`'s ceiling, not of
/// the speaker, so the slider's middle is what the app has always played.
enum AppSound {
  /// Two falling notes, F5 to D5: above the call's cues, which sit around A4,
  /// so a message is never mistaken for somebody joining, and falling where
  /// join rises.
  message(
    label: 'New messages',
    description:
        'A message you would be notified about, in a conversation you are '
        'not looking at.',
    startAsset: 'audio/message.mp3',
  ),
  presence(
    label: 'Join and leave',
    description: 'Someone, you included, enters or leaves your voice channel.',
    startAsset: 'audio/join.mp3',
    endAsset: 'audio/leave.mp3',
  ),
  pushToTalk(
    label: 'Push to talk',
    description: 'Your mic opening and closing as you press and release.',
    startAsset: 'audio/ptt_on.mp3',
    endAsset: 'audio/ptt_off.mp3',
  ),
  stream(
    label: 'Streams',
    description: 'A screen share starting or ending in your channel.',
    startAsset: 'audio/stream_started.mp3',
    endAsset: 'audio/stream_ended.mp3',
  ),
  watchers(
    label: 'Viewers',
    description: 'Someone starting or stopping watching a stream you are in.',
    startAsset: 'audio/watch_started.mp3',
    endAsset: 'audio/watch_stopped.mp3',
  );

  final String label;
  final String description;
  final String startAsset;

  /// The closing half of a pair, or null for a sound that has none.
  final String? endAsset;

  const AppSound({
    required this.label,
    required this.description,
    required this.startAsset,
    this.endAsset,
  });

  /// Where a slider starts before anybody has touched it: half the ceiling,
  /// which is the level every cue played at before it could be changed.
  static const defaultVolume = 0.5;

  /// This pair's setting out of [all], or the default when it was never set.
  ParticipantSetting settingIn(Map<String, ParticipantSetting> all) =>
      all[name] ?? const ParticipantSetting(volume: defaultVolume);
}
