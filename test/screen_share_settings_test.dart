import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
import 'package:rift/data/classes/server_limits.dart';
import 'package:rift/data/classes/share_encoding.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

void main() {
  group('ScreenShareSettings.codecFromName', () {
    test('maps every codec the picker offers', () {
      expect(ScreenShareSettings.codecFromName('VP8'), VideoCodec.vp8);
      expect(ScreenShareSettings.codecFromName('H264'), VideoCodec.h264);
      expect(ScreenShareSettings.codecFromName('VP9'), VideoCodec.vp9);
    });

    test('is not case sensitive', () {
      expect(ScreenShareSettings.codecFromName('vp8'), VideoCodec.vp8);
    });

    test('falls back to the default for a codec Rust cannot publish', () {
      expect(
        ScreenShareSettings.codecFromName('AV1'),
        ScreenShareSettings.defaultCodec,
      );
      expect(ScreenShareSettings.codecFromName(''), VideoCodec.vp9);
    });
  });

  test('the default settings round-trip through JSON with a usable codec', () {
    const settings = ScreenShareSettings();
    final restored = ScreenShareSettings.fromJson(settings.toJson());
    expect(restored.videoCodec, VideoCodec.vp9);
  });

  group('codec on a computer that encodes H264 only on the GPU', () {
    const gpu = {VideoCodec.h264};
    const none = <VideoCodec>{};

    VideoCodec send(ScreenShareSettings settings, Set<VideoCodec> codecs) =>
        settings.codecToSend(gpuOnlyH264: true, gpu: codecs);

    test('Auto follows the hardware', () {
      expect(send(const ScreenShareSettings(), gpu), VideoCodec.h264);
      expect(send(const ScreenShareSettings(), none), VideoCodec.vp9);
    });

    test('Auto keeps sharpness on VP9 even with a GPU encoder', () {
      const sharp = ScreenShareSettings(priority: SharePriority.sharpness);
      expect(send(sharp, gpu), VideoCodec.vp9);
      const balanced = ScreenShareSettings(priority: SharePriority.balanced);
      expect(send(balanced, gpu), VideoCodec.h264);
    });

    test('settings saved before there was a choice are Auto', () {
      final old = ScreenShareSettings.fromJson(const {'codec': 'VP9'});
      expect(old.codecChosen, isFalse);
      expect(send(old, gpu), VideoCodec.h264);
    });

    test('a codec changed from the old default before Auto stays picked', () {
      final old = ScreenShareSettings.fromJson(const {'codec': 'VP8'});
      expect(old.codecChosen, isTrue);
      expect(send(old, gpu), VideoCodec.vp8);
    });

    test('VP9 picked by hand stays VP9', () {
      const picked = ScreenShareSettings(codec: 'VP9', codecChosen: true);
      expect(send(picked, gpu), VideoCodec.vp9);
      final restored = ScreenShareSettings.fromJson(picked.toJson());
      expect(send(restored, gpu), VideoCodec.vp9);
    });

    test('a saved H264 with no GPU to encode it goes out as VP9', () {
      const picked = ScreenShareSettings(codec: 'H264', codecChosen: true);
      expect(send(picked, none), VideoCodec.vp9);
      expect(send(picked, gpu), VideoCodec.h264);
    });

    test('VP8 is kept either way', () {
      const picked = ScreenShareSettings(codec: 'VP8', codecChosen: true);
      expect(send(picked, gpu), VideoCodec.vp8);
      expect(send(picked, none), VideoCodec.vp8);
    });

    test('H264 is offered only where the GPU encodes it', () {
      expect(ScreenShareSettings.codecsOffered(gpuOnlyH264: true, gpu: none), [
        VideoCodec.vp8,
        VideoCodec.vp9,
      ]);
      expect(ScreenShareSettings.codecsOffered(gpuOnlyH264: true, gpu: gpu), [
        VideoCodec.vp8,
        VideoCodec.h264,
        VideoCodec.vp9,
      ]);
    });

    test('the choice survives picking a window', () {
      final settings =
          const ScreenShareSettings(
            codec: 'VP9',
            codecChosen: true,
          ).withVideoSource(
            const CaptureSource(index: 0, title: 'Game', minimised: false),
          );
      expect(settings.codecChosen, isTrue);
    });
  });

  group('codec elsewhere', () {
    test('Auto is VP9, since nothing says a GPU encodes H264', () {
      expect(
        const ScreenShareSettings().codecToSend(
          gpuOnlyH264: false,
          gpu: const {},
        ),
        VideoCodec.vp9,
      );
    });

    test('one picked by hand is sent as picked', () {
      const h264 = ScreenShareSettings(codec: 'H264', codecChosen: true);
      expect(
        h264.codecToSend(gpuOnlyH264: false, gpu: const {}),
        VideoCodec.h264,
      );
      expect(
        ScreenShareSettings.codecsOffered(gpuOnlyH264: false, gpu: const {}),
        [VideoCodec.vp8, VideoCodec.h264, VideoCodec.vp9],
      );
    });
  });

  group('120 fps', () {
    test('is offered up to 1080p on the CPU and 2K on the GPU', () {
      List<int> at(int height, {required bool onGpu}) =>
          ScreenShareSettings.frameRatesAt(height, onGpu: onGpu);
      expect(at(1080, onGpu: false), [15, 30, 60, 120]);
      expect(at(1440, onGpu: false), [15, 30, 60]);
      expect(at(1440, onGpu: true), [15, 30, 60, 120]);
      expect(at(2160, onGpu: true), [15, 30, 60]);
    });

    test('a picture too big for it goes out at 60, keeping the choice', () {
      const settings = ScreenShareSettings(resolution: 1440, fps: 120);
      expect(settings.fpsToSend(onGpu: true), 120);
      expect(settings.fpsToSend(onGpu: false), 60);
      expect(settings.copyWith(resolution: 1080).fpsToSend(onGpu: false), 120);
    });

    test('lower rates go out as picked at any size', () {
      const settings = ScreenShareSettings(resolution: 2160, fps: 30);
      expect(settings.fpsToSend(onGpu: false), 30);
    });

    test('Auto bitrate follows the rate sent, not the one picked', () {
      const settings = ScreenShareSettings(resolution: 2160, fps: 120);
      expect(
        settings.bitrateToSend(
          codec: VideoCodec.vp9,
          onGpu: false,
          limits: const ServerLimits(),
        ),
        ShareEncoding.autoMbps(
          resolution: 2160,
          fps: 60,
          codec: VideoCodec.vp9,
        ),
      );
    });

    test('only H264, and only where it is GPU-only, counts as the GPU', () {
      expect(
        ScreenShareSettings.encodedOnGpu(VideoCodec.h264, gpuOnlyH264: true),
        isTrue,
      );
      expect(
        ScreenShareSettings.encodedOnGpu(VideoCodec.h264, gpuOnlyH264: false),
        isFalse,
      );
      expect(
        ScreenShareSettings.encodedOnGpu(VideoCodec.vp9, gpuOnlyH264: true),
        isFalse,
      );
    });
  });

  group('bitrate', () {
    const open = ServerLimits();

    test('Auto follows the picture and the codec', () {
      const settings = ScreenShareSettings(resolution: 720, fps: 30);
      expect(
        settings.bitrateToSend(
          codec: VideoCodec.vp9,
          onGpu: false,
          limits: open,
        ),
        ShareEncoding.autoMbps(resolution: 720, fps: 30, codec: VideoCodec.vp9),
      );
    });

    test('one picked by hand is sent as picked', () {
      const settings = ScreenShareSettings(bitrate: 4, bitrateChosen: true);
      expect(
        settings.bitrateToSend(
          codec: VideoCodec.h264,
          onGpu: true,
          limits: open,
        ),
        4,
      );
    });

    test('neither goes over what the server allows', () {
      const capped = ServerLimits(maxShareMbps: 3);
      expect(
        const ScreenShareSettings().bitrateToSend(
          codec: VideoCodec.h264,
          onGpu: true,
          limits: capped,
        ),
        3,
      );
      expect(
        const ScreenShareSettings(
          bitrate: 15,
          bitrateChosen: true,
        ).bitrateToSend(codec: VideoCodec.vp9, onGpu: false, limits: capped),
        3,
      );
    });

    test('settings saved at the old default are Auto, others stay picked', () {
      expect(
        ScreenShareSettings.fromJson(const {'bitrate': 10}).bitrateChosen,
        isFalse,
      );
      expect(
        ScreenShareSettings.fromJson(const {'bitrate': 6}).bitrateChosen,
        isTrue,
      );
      const picked = ScreenShareSettings(bitrate: 10, bitrateChosen: true);
      expect(
        ScreenShareSettings.fromJson(picked.toJson()).bitrateChosen,
        isTrue,
      );
    });
  });

  group('advanced settings', () {
    test('start closed and are remembered open', () {
      expect(const ScreenShareSettings().showsAdvanced, isFalse);
      const open = ScreenShareSettings(showsAdvanced: true);
      expect(ScreenShareSettings.fromJson(open.toJson()).showsAdvanced, isTrue);
    });

    test('stay open after picking a window', () {
      final settings = const ScreenShareSettings(showsAdvanced: true)
          .withVideoSource(
            const CaptureSource(index: 0, title: 'Game', minimised: false),
          );
      expect(settings.showsAdvanced, isTrue);
    });
  });

  group('priority', () {
    test('starts on smoothness', () {
      expect(const ScreenShareSettings().priority, SharePriority.smoothness);
    });

    test('is remembered across a restart', () {
      const settings = ScreenShareSettings(priority: SharePriority.sharpness);
      final restored = ScreenShareSettings.fromJson(settings.toJson());
      expect(restored.priority, SharePriority.sharpness);
    });

    test('settings saved before it existed get the default', () {
      final restored = ScreenShareSettings.fromJson(const {'fps': 30});
      expect(restored.priority, SharePriority.smoothness);
      expect(restored.fps, 30);
    });

    test('a name this build does not know gets the default', () {
      expect(
        ScreenShareSettings.priorityFromName('motion'),
        SharePriority.smoothness,
      );
    });

    test('survives picking a window', () {
      final settings =
          const ScreenShareSettings(
            priority: SharePriority.balanced,
          ).withVideoSource(
            const CaptureSource(index: 0, title: 'Game', minimised: false),
          );
      expect(settings.priority, SharePriority.balanced);
    });
  });

  test('a picked window keeps its title across a restart', () {
    final settings = const ScreenShareSettings().withVideoSource(
      const CaptureSource(
        index: 2,
        title: 'Explorer',
        audioSourcePid: 10,
        minimised: false,
      ),
    );
    final restored = ScreenShareSettings.fromJson(settings.toJson());
    expect(restored.selectedVideoSourceTitle, 'Explorer');
    expect(restored.selectedVideoSourcePid, 10);
  });

  test("picking a window without a process drops the last one's", () {
    final settings = const ScreenShareSettings(selectedVideoSourcePid: 10)
        .withVideoSource(
          const CaptureSource(index: 0, title: 'Screen', minimised: false),
        );
    expect(settings.selectedVideoSourcePid, isNull);
  });
}
