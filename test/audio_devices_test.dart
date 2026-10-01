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
  AudioEndpoint endpoint({
    required int channels,
    required int sampleRate,
    required bool opens,
  }) => AudioEndpoint(
    deviceId: '{0.0.0.00000000}.{a}',
    name: 'Test',
    channels: channels,
    sampleRate: sampleRate,
    opens: opens,
  );

  group('unusableFormat', () {
    test('accepts whatever Windows says the module can open', () {
      expect(
        AudioDevices.unusableFormat(
          endpoint(channels: 2, sampleRate: 48000, opens: true),
        ),
        isNull,
      );
      // Seen on Windows: a laptop's stereo speakers reported an 8 channel mix
      // inside Rift's process while WebRTC played through them. Refusing on
      // the mix format made "System default" impossible to go back to.
      expect(
        AudioDevices.unusableFormat(
          endpoint(channels: 8, sampleRate: 48000, opens: true),
        ),
        isNull,
      );
    });

    test('refuses what Windows says it cannot open, and says the format', () {
      // The usual shape of a virtual device belonging to routing software.
      expect(
        AudioDevices.unusableFormat(
          endpoint(channels: 8, sampleRate: 96000, opens: false),
        ),
        '8 channel 96 kHz',
      );
      expect(
        AudioDevices.unusableFormat(
          endpoint(channels: 2, sampleRate: 22050, opens: false),
        ),
        '2 channel 22.1 kHz',
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
