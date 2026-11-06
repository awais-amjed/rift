// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/utils.dart' show Utils;
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/data/classes/server_limits.dart';
import 'package:rift/logic/services/phone_share_publish.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

void main() {
  const all = [VideoCodec.vp8, VideoCodec.h264, VideoCodec.vp9];
  const noH264 = [VideoCodec.vp8];
  const unlimited = ServerLimits();

  ScreenShareSettings opened({int shortSide = 1080}) => PhoneShare.opening(
    const ScreenShareSettings(),
    shortSide: shortSide,
    frameRates: PhoneShare.frameRatesFor(60),
  );

  group('what is offered', () {
    test('a screen offers its own height and the ones below, never above', () {
      expect(PhoneShare.resolutionsFor(1080), [360, 480, 720, 1080]);
      expect(PhoneShare.resolutionsFor(720), [360, 480, 720]);
      expect(PhoneShare.resolutionsFor(1440), [360, 480, 720, 1080, 1440]);
      expect(PhoneShare.resolutionsFor(1220), [360, 480, 720, 1080, 1220]);
    });

    test('a screen whose size is not known still offers something', () {
      expect(PhoneShare.resolutionsFor(0), [360, 480, 720, 1080]);
    });

    test('the codecs are the ones the phone lists, with VP8 on any', () {
      expect(
        PhoneShare.codecsOf([
          'video/VP8',
          'video/rtx',
          'video/VP9',
          'video/H264',
        ]),
        all,
      );
      expect(PhoneShare.codecsOf(['video/VP8', 'video/rtx']), noH264);
      expect(PhoneShare.codecsOf(const []), noH264);
    });
  });

  group('what the dialog opens on', () {
    test('settings no phone confirmed open on the whole screen at 30', () {
      final settings = opened(shortSide: 1440);
      expect(settings.resolution, 1440);
      expect(settings.fps, 30);
      expect(settings.codecChosen, isFalse);
      expect(settings.bitrateChosen, isFalse);
    });

    test('what a phone confirmed is kept', () {
      const saved = ScreenShareSettings(
        phoneSetUp: true,
        resolution: 720,
        fps: 60,
        codec: 'VP9',
        codecChosen: true,
      );
      expect(
        PhoneShare.opening(
          saved,
          shortSide: 1080,
          frameRates: PhoneShare.frameRatesFor(60),
        ),
        saved,
      );
    });

    test('a saved height or rate this phone cannot send goes back', () {
      const saved = ScreenShareSettings(
        phoneSetUp: true,
        resolution: 1440,
        fps: 120,
      );
      final settings = PhoneShare.opening(
        saved,
        shortSide: 1080,
        frameRates: PhoneShare.frameRatesFor(60),
      );
      expect(settings.resolution, 1080);
      expect(settings.fps, 30);
    });

    test('a saved 120 stays on a screen that can run it', () {
      const saved = ScreenShareSettings(phoneSetUp: true, fps: 120);
      final settings = PhoneShare.opening(
        saved,
        shortSide: 1080,
        frameRates: PhoneShare.frameRatesFor(120),
      );
      expect(settings.fps, 120);
    });

    test('120 is offered only on a screen that can run it', () {
      expect(PhoneShare.frameRatesFor(60), [15, 30, 60]);
      expect(PhoneShare.frameRatesFor(90), [15, 30, 60]);
      expect(PhoneShare.frameRatesFor(119.88), [15, 30, 60, 120]);
      expect(PhoneShare.frameRatesFor(120.00001), [15, 30, 60, 120]);
      expect(PhoneShare.frameRatesFor(144), [15, 30, 60, 120]);
    });

    test('the flag survives a save, and old saves have none', () {
      const saved = ScreenShareSettings(phoneSetUp: true);
      expect(ScreenShareSettings.fromJson(saved.toJson()).phoneSetUp, isTrue);
      expect(ScreenShareSettings.fromJson(const {}).phoneSetUp, isFalse);
    });
  });

  group('the codec', () {
    test('Auto is H264 where the phone has it, otherwise VP8', () {
      expect(PhoneShare.codecToSend(opened(), all), VideoCodec.h264);
      expect(PhoneShare.codecToSend(opened(), noH264), VideoCodec.vp8);
    });

    test('a codec picked by hand goes out as picked', () {
      final settings = opened().copyWith(codec: 'VP9', codecChosen: true);
      expect(PhoneShare.codecToSend(settings, all), VideoCodec.vp9);
    });

    test('one this phone does not have goes back to Auto', () {
      final settings = opened().copyWith(codec: 'H264', codecChosen: true);
      expect(PhoneShare.codecToSend(settings, noH264), VideoCodec.vp8);
    });
  });

  group('the bitrate', () {
    int auto(ScreenShareSettings settings, VideoCodec codec) =>
        settings.bitrateToSend(codec: codec, limits: unlimited);

    test('Auto asks what a desktop asks in the codec going out', () {
      for (final (codec, name) in [
        (VideoCodec.h264, 'H264'),
        (VideoCodec.vp8, 'VP8'),
        (VideoCodec.vp9, 'VP9'),
      ]) {
        final settings = opened().copyWith(codec: name, codecChosen: true);
        final sent = PhoneShare.request(
          settings,
          codecs: all,
          limits: unlimited,
        ).publish.screenShareEncoding!.maxBitrate;
        expect(sent, auto(settings, codec) * 1000 * 1000);
      }
      expect(auto(opened(), VideoCodec.h264), 11);
    });

    test('one picked by hand is sent, held to the server', () {
      final settings = opened().copyWith(bitrate: 20, bitrateChosen: true);
      expect(auto(settings, VideoCodec.h264), 20);
      expect(
        settings.bitrateToSend(
          codec: VideoCodec.h264,
          limits: const ServerLimits(maxShareMbps: 8),
        ),
        8,
      );
    });
  });

  group('how it goes out', () {
    test('each choice reaches the publish options', () {
      final request = PhoneShare.request(
        opened().copyWith(
          resolution: 720,
          fps: 60,
          priority: SharePriority.sharpness,
          bitrate: 12,
          bitrateChosen: true,
          codec: 'VP8',
          codecChosen: true,
        ),
        codecs: all,
        limits: unlimited,
      );
      final publish = request.publish;
      expect(publish.videoCodec, 'vp8');
      expect(publish.screenShareEncoding!.maxFramerate, 60);
      expect(publish.screenShareEncoding!.maxBitrate, 12 * 1000 * 1000);
      expect(
        publish.degradationPreference,
        DegradationPreference.maintainResolution,
      );
      expect(request.capture.toMediaConstraintsMap()['riftShortSide'], 720);
    });

    test('one picture goes out, with what was asked', () {
      for (final codec in ['h264', 'vp8']) {
        final encodings = Utils.computeVideoEncodings(
          isScreenShare: true,
          dimensions: VideoDimensionsPresets.h1080_169,
          options: PhoneShare.request(
            opened().copyWith(fps: 60, codec: codec, codecChosen: true),
            codecs: all,
            limits: unlimited,
          ).publish,
          codec: codec,
        )!;

        expect(encodings, hasLength(1));
        expect(encodings.single.maxFramerate, 60);
        expect(encodings.single.scaleResolutionDownBy ?? 1, 1);
      }
    });

    test('a backup codec would send one picture as well', () {
      final publish = PhoneShare.request(
        opened(),
        codecs: all,
        limits: unlimited,
      ).publish;
      expect(publish.backupVideoCodec.simulcast, isFalse);
    });

    test('a server limit is the whole of what is sent', () {
      final request = PhoneShare.request(
        opened(),
        codecs: all,
        limits: const ServerLimits(maxShareMbps: 3),
      );
      expect(request.publish.screenShareEncoding!.maxBitrate, 3 * 1000 * 1000);
    });

    test('with no limit, the whole of Auto goes out', () {
      final request = PhoneShare.request(
        opened(),
        codecs: all,
        limits: unlimited,
      );
      expect(request.publish.screenShareEncoding!.maxBitrate, 11 * 1000 * 1000);
    });
  });
}
