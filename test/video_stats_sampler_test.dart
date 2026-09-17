import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rift/logic/services/video_stats_sampler.dart';

/// Report timestamps are microseconds, so one second is 1e6.
const _oneSecond = 1000000.0;

StatsReport inbound({
  required double at,
  int? bytesReceived,
  int? framesDecoded,
  int? framesDropped,
  int width = 1920,
  int height = 1080,
  Map<String, dynamic> extra = const {},
}) => StatsReport('in', 'inbound-rtp', at, {
  'kind': 'video',
  'frameWidth': width,
  'frameHeight': height,
  'bytesReceived': ?bytesReceived,
  'framesDecoded': ?framesDecoded,
  'framesDropped': ?framesDropped,
  ...extra,
});

void main() {
  group('VideoStatsSampler', () {
    test('no rates on the first poll — they need two', () {
      final stats = VideoStatsSampler().sample([
        inbound(at: 0, bytesReceived: 1000, framesDecoded: 10),
      ]);
      expect(stats!.resolutionLabel, '1920x1080');
      expect(stats.bitrateKbps, isNull);
      expect(stats.fps, isNull);
    });

    test('falls back to the reported FPS until a rate exists', () {
      final stats = VideoStatsSampler().sample([
        inbound(at: 0, extra: {'framesPerSecond': 24}),
      ]);
      expect(stats!.fps, 24);
    });

    test('computes bitrate, FPS and dropped frames across two polls', () {
      final sampler = VideoStatsSampler();
      sampler.sample([
        inbound(at: 0, bytesReceived: 0, framesDecoded: 0, framesDropped: 0),
      ]);
      final stats = sampler.sample([
        inbound(
          at: _oneSecond,
          bytesReceived: 125000,
          framesDecoded: 30,
          framesDropped: 2,
        ),
      ]);

      // 125 kB/s = 1000 Kbps.
      expect(stats!.bitrateKbps, closeTo(1000, 0.001));
      expect(stats.bitrateLabel, '1.0 Mbps');
      expect(stats.fps, closeTo(30, 0.001));
      expect(stats.framesDroppedPerSec, 2);
    });

    test(
      'a repeated timestamp yields no rates rather than a divide by zero',
      () {
        final sampler = VideoStatsSampler();
        sampler.sample([inbound(at: 500, bytesReceived: 10, framesDecoded: 1)]);
        final stats = sampler.sample([
          inbound(at: 500, bytesReceived: 99999, framesDecoded: 99),
        ]);
        expect(stats!.bitrateKbps, isNull);
        expect(stats.fps, isNull);
      },
    );

    test('counters going backwards report nothing, never a negative rate', () {
      final sampler = VideoStatsSampler();
      sampler.sample([
        inbound(
          at: 0,
          bytesReceived: 5000,
          framesDecoded: 50,
          framesDropped: 9,
        ),
      ]);
      final stats = sampler.sample([
        inbound(
          at: _oneSecond,
          bytesReceived: 10,
          framesDecoded: 1,
          framesDropped: 0,
        ),
      ]);
      expect(stats!.bitrateKbps, isNull);
      expect(stats.fps, isNull);
      expect(stats.framesDroppedPerSec, 0);
    });

    test('resolves the codec mime type and the candidate-pair RTT', () {
      final stats = VideoStatsSampler().sample([
        StatsReport('c1', 'codec', 0, {'mimeType': 'video/VP9'}),
        StatsReport('p1', 'candidate-pair', 0, {
          'state': 'failed',
          'currentRoundTripTime': 9.0,
        }),
        StatsReport('p2', 'candidate-pair', 0, {
          'state': 'succeeded',
          'currentRoundTripTime': 0.042,
        }),
        inbound(at: 0, extra: {'codecId': 'c1', 'jitter': 0.004}),
      ]);
      expect(stats!.codec, 'VP9');
      expect(stats.rttMs, closeTo(42, 0.001));
      expect(stats.jitterMs, closeTo(4, 0.001));
    });

    test('reports nothing while the video track is not yet inbound', () {
      expect(
        VideoStatsSampler().sample([
          StatsReport('in', 'inbound-rtp', 0, {'kind': 'audio'}),
        ]),
        isNull,
      );
      expect(VideoStatsSampler().sample([]), isNull);
    });

    test('bitrate is labelled in Kbps below one Mbps', () {
      const stats = VideoStreamStats(bitrateKbps: 640.4);
      expect(stats.bitrateLabel, '640 Kbps');
      expect(const VideoStreamStats().bitrateLabel, isNull);
    });

    test('the overlay stays hidden until resolution is known', () {
      expect(const VideoStreamStats(width: 1920).hasResolution, isFalse);
      expect(
        const VideoStreamStats(width: 1920, height: 1080).hasResolution,
        isTrue,
      );
    });
  });

  group('VideoStreamStats.qualityLabel', () {
    test('names a window capture by its nearest picture class', () {
      const stats = VideoStreamStats(width: 1920, height: 1048, fps: 59.4);
      expect(stats.qualityLabel, '1080p · 60fps');
    });

    test('uses the shorter side for a tall picture', () {
      const stats = VideoStreamStats(width: 720, height: 1280, fps: 30);
      expect(stats.qualityLabel, '720p · 30fps');
    });

    test('leaves the rate out until there is one', () {
      const stats = VideoStreamStats(width: 1280, height: 720);
      expect(stats.qualityLabel, '720p');
    });

    test('says nothing without a picture size', () {
      expect(const VideoStreamStats(fps: 60).qualityLabel, isNull);
    });
  });
}
