import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/data/classes/server_limits.dart';
import 'package:rift/logic/services/web_share_publish.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

/// A browser's share: what its dialog opens on, and how a choice goes out.
void main() {
  const all = [VideoCodec.vp8, VideoCodec.h264, VideoCodec.vp9];
  const unlimited = ServerLimits();

  group('what the dialog opens on', () {
    test('settings no browser confirmed open on 1080p30 with sound', () {
      final opened = WebShare.opening(
        const ScreenShareSettings(shareAudio: false, codecChosen: true),
      );
      expect(opened.resolution, 1080);
      expect(opened.fps, 30);
      expect(opened.shareAudio, isTrue);
      expect(opened.codecChosen, isFalse);
    });

    test('what a browser confirmed is kept', () {
      final opened = WebShare.opening(
        const ScreenShareSettings(
          resolution: 1440,
          fps: 60,
          shareAudio: false,
          phoneSetUp: true,
        ),
      );
      expect(opened.resolution, 1440);
      expect(opened.fps, 60);
      expect(opened.shareAudio, isFalse);
    });

    test('a saved rate a browser cannot capture goes back', () {
      final opened = WebShare.opening(
        const ScreenShareSettings(fps: 120, phoneSetUp: true),
      );
      expect(opened.fps, WebShare.defaultFps);
    });
  });

  group('the codec', () {
    test('Auto is H264 where the browser encodes it in hardware', () {
      expect(
        WebShare.codecToSend(
          const ScreenShareSettings(),
          all,
          hardwareH264: true,
        ),
        VideoCodec.h264,
      );
    });

    test('Auto is VP9 where H264 would be software', () {
      expect(
        WebShare.codecToSend(
          const ScreenShareSettings(),
          all,
          hardwareH264: false,
        ),
        VideoCodec.vp9,
      );
    });

    test('Auto is VP8 where the browser has nothing else', () {
      expect(
        WebShare.autoCodec(const [VideoCodec.vp8], hardwareH264: true),
        VideoCodec.vp8,
      );
      expect(
        WebShare.autoCodec(const [
          VideoCodec.vp8,
          VideoCodec.h264,
        ], hardwareH264: false),
        VideoCodec.vp8,
      );
    });

    test('one picked by hand goes out, unless the browser lacks it', () {
      const vp8 = ScreenShareSettings(codec: 'VP8', codecChosen: true);
      expect(
        WebShare.codecToSend(vp8, all, hardwareH264: true),
        VideoCodec.vp8,
      );
      const vp9 = ScreenShareSettings(codec: 'VP9', codecChosen: true);
      expect(
        WebShare.codecToSend(vp9, const [VideoCodec.vp8], hardwareH264: false),
        VideoCodec.vp8,
      );
    });
  });

  group('how it goes out', () {
    test('the capture asks for no more than was chosen, in any shape', () {
      final request = WebShare.request(
        const ScreenShareSettings(resolution: 720, fps: 60, shareAudio: true),
        codecs: all,
        hardwareH264: false,
        limits: unlimited,
      );
      final capture = request.capture;
      expect(capture.captureScreenAudio, isTrue);
      expect(capture.toMediaConstraintsMap(), {
        'height': {'max': 720},
        'frameRate': {'ideal': 60, 'max': 60},
      });
      expect(request.publish.screenShareEncoding!.maxFramerate, 60);
      expect(request.publish.videoCodec, 'vp9');
    });

    test('asking for sound keeps the size and rate', () {
      final capture = WebShare.request(
        const ScreenShareSettings(resolution: 1440, fps: 60, shareAudio: false),
        codecs: all,
        hardwareH264: false,
        limits: unlimited,
      ).capture.copyWith(captureScreenAudio: true);
      expect(capture.captureScreenAudio, isTrue);
      expect(capture.toMediaConstraintsMap(), {
        'height': {'max': 1440},
        'frameRate': {'ideal': 60, 'max': 60},
      });
    });

    test('sound is asked of the browser only when chosen', () {
      final request = WebShare.request(
        const ScreenShareSettings(shareAudio: false),
        codecs: all,
        hardwareH264: false,
        limits: unlimited,
      );
      expect(request.capture.captureScreenAudio, isFalse);
    });

    test('one picture, held to the server', () {
      final publish = WebShare.request(
        const ScreenShareSettings(resolution: 1080, fps: 30),
        codecs: all,
        hardwareH264: false,
        limits: const ServerLimits(maxShareMbps: 3),
      ).publish;
      expect(publish.simulcast, isFalse);
      expect(publish.screenShareEncoding!.maxBitrate, 3 * 1000 * 1000);
    });
  });
}
