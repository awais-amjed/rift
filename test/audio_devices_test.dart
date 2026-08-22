import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rift/logic/services/audio_devices.dart';

/// The gate on which endpoints may be selected.
///
/// This is not a cosmetic filter. Handing WebRTC's Windows device module an
/// endpoint it cannot open stops playout, and its own device-change path only
/// restarts playout that was already running — so one bad pick silences the
/// call through every later choice until it is rejoined. Both a hand-picked
/// device and a saved one applied on join go through here.
void main() {
  AudioEndpoint endpoint({required int channels, required int sampleRate}) =>
      AudioEndpoint(
        deviceId: '{0.0.0.00000000}.{a}',
        name: 'Test',
        channels: channels,
        sampleRate: sampleRate,
      );

  group('unusableFormat', () {
    test('accepts mono and stereo at every rate the module tries', () {
      for (final rate in [8000, 16000, 32000, 44100, 48000, 96000]) {
        expect(
          AudioDevices.unusableFormat(endpoint(channels: 1, sampleRate: rate)),
          isNull,
          reason: '$rate Hz mono',
        );
        expect(
          AudioDevices.unusableFormat(endpoint(channels: 2, sampleRate: rate)),
          isNull,
          reason: '$rate Hz stereo',
        );
      }
    });

    test('refuses more than two channels, and says the format', () {
      // The usual shape of a virtual device belonging to routing software.
      // Windows converts bit depth for a shared stream but not channel count.
      expect(
        AudioDevices.unusableFormat(endpoint(channels: 8, sampleRate: 96000)),
        '8 channel 96 kHz',
      );
    });

    test('refuses a rate the module never asks for', () {
      expect(
        AudioDevices.unusableFormat(endpoint(channels: 2, sampleRate: 192000)),
        '2 channel 192 kHz',
      );
      expect(
        AudioDevices.unusableFormat(endpoint(channels: 2, sampleRate: 22050)),
        '2 channel 22.1 kHz',
      );
    });

    test('refuses an endpoint reporting no channels at all', () {
      expect(
        AudioDevices.unusableFormat(endpoint(channels: 0, sampleRate: 48000)),
        '0 channel 48 kHz',
      );
    });

    test('an endpoint nothing is known about is not refused', () {
      // Off Windows, and whenever the WASAPI probe fails, the format map is
      // empty. That has to read as "do not filter" — refusing on a failed
      // probe would hide every device that would have worked fine.
      expect(AudioDevices.unusableFormat(null), isNull);
    });
  });

  group('byId', () {
    const devices = <MediaDevice>[
      MediaDevice('id-a', 'Headset', 'audiooutput', null),
      MediaDevice('id-b', 'Speakers', 'audiooutput', null),
    ];

    test('finds a device that is present', () {
      expect(AudioDevices.byId(devices, 'id-b')?.label, 'Speakers');
    });

    test('an id the list does not hold gives null, never a substitute', () {
      // The old code fell back to the first device, which turned a saved id
      // from another machine into a silent switch to an unrelated device.
      expect(AudioDevices.byId(devices, 'id-gone'), isNull);
      expect(AudioDevices.byId(devices, null), isNull);
      expect(AudioDevices.byId(const [], 'id-a'), isNull);
    });
  });

  group('labelOf', () {
    test('stands in for the empty label the platform gives before '
        'permission', () {
      expect(
        AudioDevices.labelOf(MediaDevice('id', '', 'audioinput', null)),
        'Unknown',
      );
      expect(
        AudioDevices.labelOf(MediaDevice('id', 'Yeti', 'audioinput', null)),
        'Yeti',
      );
    });
  });
}
