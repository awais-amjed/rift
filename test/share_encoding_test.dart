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
      final heights = [360, 480, 720, 1080, 1440, 2160];
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
      expect(
        mbps(1080, 120, VideoCodec.vp9),
        greaterThan(mbps(1080, 60, VideoCodec.vp9)),
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

    test('asks less of H264 in High profile', () {
      int high(int resolution, int fps) => ShareEncoding.autoMbps(
        resolution: resolution,
        fps: fps,
        codec: VideoCodec.h264,
        h264High: true,
      );
      expect(high(1080, 60), 12);
      expect(high(1080, 30), 8);
      expect(high(1080, 120), 18);
      expect(mbps(1080, 60, VideoCodec.h264), 15);
    });

    test('High changes nothing for the other codecs', () {
      for (final codec in [VideoCodec.vp8, VideoCodec.vp9]) {
        expect(
          ShareEncoding.autoMbps(
            resolution: 1080,
            fps: 60,
            codec: codec,
            h264High: true,
          ),
          mbps(1080, 60, codec),
        );
      }
    });

    test('has no ceiling of its own, and never goes under 1 Mbps', () {
      expect(mbps(1440, 120, VideoCodec.h264), 34);
      expect(mbps(2160, 60, VideoCodec.h264), 38);
      expect(mbps(240, 15, VideoCodec.vp9), 1);
    });

    test('sizes a height not in the table by its pixels', () {
      expect(mbps(1200, 60, VideoCodec.vp9), inInclusiveRange(10, 15));
    });
  });

  group('Auto with H265 on the GPU', () {
    test('takes H265 for smoothness', () {
      expect(
        ShareEncoding.autoCodec(
          priority: SharePriority.smoothness,
          gpuH264: true,
          gpuH265: true,
        ),
        VideoCodec.h265,
      );
    });

    test('keeps VP9 for sharpness', () {
      expect(
        ShareEncoding.autoCodec(
          priority: SharePriority.sharpness,
          gpuH264: true,
          gpuH265: true,
        ),
        VideoCodec.vp9,
      );
    });

    test('asks 10 Mbps at 1080p60, where H264 High asks 12', () {
      expect(
        ShareEncoding.autoMbps(
          resolution: 1080,
          fps: 60,
          codec: VideoCodec.h265,
        ),
        10,
      );
      expect(
        ShareEncoding.autoMbps(
          resolution: 1080,
          fps: 60,
          codec: VideoCodec.h264,
          h264High: true,
        ),
        12,
      );
    });
  });
}
