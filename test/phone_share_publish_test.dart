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
      expect(PhoneShare.resolutionsFor(1080), [480, 720, 1080]);
      expect(PhoneShare.resolutionsFor(720), [480, 720]);
      expect(PhoneShare.resolutionsFor(1440), [480, 720, 1080, 1440]);
      expect(PhoneShare.resolutionsFor(1220), [480, 720, 1080, 1220]);
    });

    test('a screen whose size is not known still offers something', () {
      expect(PhoneShare.resolutionsFor(0), [480, 720, 1080]);
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
    test('Auto keeps 1080p at 30 fps in H264 at the measured 5 Mbps', () {
      expect(PhoneShare.mbpsToSend(opened(), limits: unlimited), 5);
    });

    test('Auto follows the picture, and never goes below 2', () {
      int auto(int resolution, int fps) =>
          PhoneShare.autoMbps(resolution: resolution, fps: fps);
      expect(auto(1080, 60), greaterThan(auto(1080, 30)));
      expect(auto(720, 30), lessThan(auto(1080, 30)));
      expect(auto(480, 15), 2);
      expect(auto(720, 60), 4);
    });

    test('one picked by hand is sent, held to the server', () {
      final settings = opened().copyWith(bitrate: 20, bitrateChosen: true);
      expect(PhoneShare.mbpsToSend(settings, limits: unlimited), 20);
      expect(
        PhoneShare.mbpsToSend(
          settings,
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

    test('the encoding reaches the sent picture, not only the options', () {
      final encodings = Utils.computeVideoEncodings(
        isScreenShare: true,
        dimensions: VideoDimensionsPresets.h1080_169,
        options: PhoneShare.request(
          opened().copyWith(fps: 60),
          codecs: all,
          limits: unlimited,
        ).publish,
        codec: 'h264',
      )!;

      expect(encodings.last.maxFramerate, 60);
    });

    test('everything sent stays within a server limit', () {
      final encodings = Utils.computeVideoEncodings(
        isScreenShare: true,
        dimensions: VideoDimensionsPresets.h1080_169,
        options: PhoneShare.request(
          opened(),
          codecs: all,
          limits: const ServerLimits(maxShareMbps: 3),
        ).publish,
        codec: 'h264',
      )!;

      expect(encodings.length, greaterThan(1));
      final total = encodings.fold(0, (sum, e) => sum + e.maxBitrate!);
      expect(total, lessThanOrEqualTo(3 * 1000 * 1000));
    });

    test('with no limit, nothing is held back for the second picture', () {
      final request = PhoneShare.request(
        opened(),
        codecs: all,
        limits: unlimited,
      );
      expect(request.publish.screenShareEncoding!.maxBitrate, 5 * 1000 * 1000);
    });
  });
}
