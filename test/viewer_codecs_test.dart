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

  group('ViewerCodecs.onDevice', () {
    const listed = {VideoCodec.vp8, VideoCodec.vp9, VideoCodec.h264};

    test('a desktop decoding on the GPU says H264 and H265', () {
      expect(
        ViewerCodecs.onDevice(
          listed,
          gpuDecodesOnly: true,
          gpuPlaysH264: true,
          gpuPlaysH265: true,
        ),
        {...listed, VideoCodec.h265},
      );
    });

    test('a desktop that would decode H264 on the CPU does not say it', () {
      expect(
        ViewerCodecs.onDevice(
          listed,
          gpuDecodesOnly: true,
          gpuPlaysH264: false,
          gpuPlaysH265: false,
        ),
        {VideoCodec.vp8, VideoCodec.vp9},
      );
    });

    test('a phone or browser keeps what WebRTC lists', () {
      expect(
        ViewerCodecs.onDevice(
          listed,
          gpuDecodesOnly: false,
          gpuPlaysH264: false,
          gpuPlaysH265: false,
        ),
        listed,
      );
    });
  });

  group('ViewerCodecs.withoutGpu', () {
    const plays = {
      VideoCodec.vp8,
      VideoCodec.vp9,
      VideoCodec.h264,
      VideoCodec.h265,
    };

    test('the watch connection working changes nothing', () {
      expect(ViewerCodecs.withoutGpu(plays, rustWatchGaveOut: false), plays);
    });

    test('the call\'s own connection takes neither H264 nor H265', () {
      expect(ViewerCodecs.withoutGpu(plays, rustWatchGaveOut: true), {
        VideoCodec.vp8,
        VideoCodec.vp9,
      });
    });
  });
}
