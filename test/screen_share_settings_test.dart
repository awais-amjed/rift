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
}
