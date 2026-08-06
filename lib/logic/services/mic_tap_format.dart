import 'package:livekit_client/livekit_client.dart';

/// The PCM format both microphone taps ask the native side for: the one
/// running during a call for the noise gate and the speaking indicator, and
/// the one the mic test opens when no call holds the device.
///
/// One constant rather than two matching literals, because the two taps feed
/// the same meter and the same threshold. If they disagreed, the bar would
/// read differently depending on whether you were in a call — which is the
/// bug that made the threshold marker meaningless in the first place.
///
/// Mono, because this is a level and not a mix. 16 kHz because a level needs
/// energy rather than bandwidth, and the frames cross a platform channel a
/// hundred times a second — asking for the microphone's full 48 kHz would
/// triple that traffic to compute the same number.
const micTapFormat = AudioRendererOptions(
  sampleRate: 16000,
  channels: 1,
  format: AudioFormat.Int16,
);
