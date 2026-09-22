import '../classes/participant_setting.dart';

/// The cues a call plays on this device, in the pairs a person thinks of
/// them in: nobody wants the join tone and not the leave tone.
///
/// Each pair is muted and turned down as one, in `AppState.callSounds` under
/// its [name]. A volume there is a share of `SoundService`'s ceiling, not of
/// the speaker, so the slider's middle is what the app has always played.
enum CallSound {
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
  final String endAsset;

  const CallSound({
    required this.label,
    required this.description,
    required this.startAsset,
    required this.endAsset,
  });

  /// Where a slider starts before anybody has touched it: half the ceiling,
  /// which is the level every cue played at before it could be changed.
  static const defaultVolume = 0.5;

  /// This pair's setting out of [all], or the default when it was never set.
  ParticipantSetting settingIn(Map<String, ParticipantSetting> all) =>
      all[name] ?? const ParticipantSetting(volume: defaultVolume);
}
