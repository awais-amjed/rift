import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/share_encoding.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

/// What a share's Auto picks.
void main() {
  group('Auto codec', () {
    test('is H264 where the GPU encodes it, unless sharpness was asked', () {
      for (final priority in SharePriority.values) {
        expect(
          ShareEncoding.autoCodec(priority: priority, gpuH264: true),
          priority == SharePriority.sharpness
              ? VideoCodec.vp9
              : VideoCodec.h264,
          reason: priority.name,
        );
      }
    });

    test('is VP9 without a GPU encoder, whatever the priority', () {
      for (final priority in SharePriority.values) {
        expect(
          ShareEncoding.autoCodec(priority: priority, gpuH264: false),
          VideoCodec.vp9,
        );
      }
    });
  });

  group('Auto bitrate', () {
    int mbps(int resolution, int fps, VideoCodec codec) =>
        ShareEncoding.autoMbps(resolution: resolution, fps: fps, codec: codec);

    test('1080p60 VP9 is the 10 Mbps a share always started at', () {
      expect(mbps(1080, 60, VideoCodec.vp9), 10);
    });

    test('grows with the picture', () {
      final heights = [720, 1080, 1440, 2160];
      for (var i = 1; i < heights.length; i++) {
        expect(
          mbps(heights[i], 60, VideoCodec.vp9),
          greaterThan(mbps(heights[i - 1], 60, VideoCodec.vp9)),
        );
      }
      expect(
        mbps(1080, 30, VideoCodec.vp9),
        lessThan(mbps(1080, 60, VideoCodec.vp9)),
      );
      expect(
        mbps(1080, 15, VideoCodec.vp9),
        lessThan(mbps(1080, 30, VideoCodec.vp9)),
      );
    });

    test('gives H264 the most and VP9 the least for the same picture', () {
      expect(
        mbps(1080, 60, VideoCodec.h264),
        greaterThan(mbps(1080, 60, VideoCodec.vp8)),
      );
      expect(
        mbps(1080, 60, VideoCodec.vp8),
        greaterThan(mbps(1080, 60, VideoCodec.vp9)),
      );
    });

    test('never goes past its ceiling, or under 2 Mbps', () {
      expect(mbps(2160, 60, VideoCodec.h264), ShareEncoding.maxAutoMbps);
      expect(mbps(240, 15, VideoCodec.vp9), 2);
    });

    test('sizes a height not in the table by its pixels', () {
      expect(mbps(1200, 60, VideoCodec.vp9), inInclusiveRange(10, 15));
    });
  });
}
