import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/viewer_codecs.dart';
import 'package:rift/logic/services/voice_attributes.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

void main() {
  group('ViewerCodecs.fromMimeTypes', () {
    test('reads what WebRTC lists', () {
      expect(
        ViewerCodecs.fromMimeTypes(const [
          'video/VP8',
          'video/VP9',
          'video/H264',
          'video/rtx',
          'video/red',
        ]),
        {VideoCodec.vp8, VideoCodec.vp9, VideoCodec.h264},
      );
    });

    test('a device without H264 says so', () {
      expect(ViewerCodecs.fromMimeTypes(const ['video/VP8', 'video/VP9']), {
        VideoCodec.vp8,
        VideoCodec.vp9,
      });
    });

    test('H265 never comes from WebRTC: a phone lists it', () {
      expect(ViewerCodecs.fromMimeTypes(const ['video/H265', 'video/VP8']), {
        VideoCodec.vp8,
      });
    });

    test('a list naming nothing known says nothing', () {
      expect(
        ViewerCodecs.fromMimeTypes(const ['video/rtx']),
        VoiceAttributes.playsUnsaid,
      );
      expect(ViewerCodecs.fromMimeTypes(const []), VoiceAttributes.playsUnsaid);
    });
  });
}
