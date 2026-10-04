import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/screen_share_settings.dart';
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

    String send(ScreenShareSettings settings, Set<VideoCodec> codecs) =>
        settings.codecToSend(gpuOnlyH264: true, gpu: codecs);

    test('a codec never picked follows the hardware', () {
      expect(send(const ScreenShareSettings(), gpu), 'H264');
      expect(send(const ScreenShareSettings(), none), 'VP9');
    });

    test('settings saved before there was a choice follow it too', () {
      final old = ScreenShareSettings.fromJson(const {'codec': 'VP9'});
      expect(send(old, gpu), 'H264');
    });

    test('VP9 picked by hand stays VP9', () {
      const picked = ScreenShareSettings(codec: 'VP9', codecChosen: true);
      expect(send(picked, gpu), 'VP9');
      final restored = ScreenShareSettings.fromJson(picked.toJson());
      expect(send(restored, gpu), 'VP9');
    });

    test('a saved H264 with no GPU to encode it goes out as VP9', () {
      const picked = ScreenShareSettings(codec: 'H264', codecChosen: true);
      expect(send(picked, none), 'VP9');
      expect(send(picked, gpu), 'H264');
    });

    test('VP8 is kept either way', () {
      const picked = ScreenShareSettings(codec: 'VP8', codecChosen: true);
      expect(send(picked, gpu), 'VP8');
      expect(send(picked, none), 'VP8');
    });

    test('H264 is offered only where the GPU encodes it', () {
      expect(ScreenShareSettings.codecsOffered(gpuOnlyH264: true, gpu: none), [
        'VP8',
        'VP9',
      ]);
      expect(ScreenShareSettings.codecsOffered(gpuOnlyH264: true, gpu: gpu), [
        'VP8',
        'H264',
        'VP9',
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
    test('is the saved one, as it always was', () {
      const h264 = ScreenShareSettings(codec: 'H264');
      expect(h264.codecToSend(gpuOnlyH264: false, gpu: const {}), 'H264');
      expect(
        const ScreenShareSettings().codecToSend(
          gpuOnlyH264: false,
          gpu: const {},
        ),
        'VP9',
      );
      expect(
        ScreenShareSettings.codecsOffered(gpuOnlyH264: false, gpu: const {}),
        ['VP8', 'H264', 'VP9'],
      );
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
