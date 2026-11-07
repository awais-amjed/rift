import 'dart:math';

import '../../src/rust/api/screenshare/types.dart';

/// What a share's "Auto" picks: the codec, and the most it may send.
///
/// Pure, so the rule can be read and tested in one place. The codec follows
/// the hardware and the priority; the bitrate follows the picture's size,
/// rate and codec.
class ShareEncoding {
  const ShareEncoding._();

  /// The codec Auto sends.
  ///
  /// H264 where the GPU encodes it, because it leaves the CPU to whatever is
  /// being shared — usually a game. VP9 where sharpness was asked for: it
  /// keeps text crisper at the same rate, and it is all a computer without a
  /// GPU encoder has (H264 is never encoded on the CPU there).
  static VideoCodec autoCodec({
    required SharePriority priority,
    required bool gpuH264,
  }) => gpuH264 && priority != SharePriority.sharpness
      ? VideoCodec.h264
      : VideoCodec.vp9;

  /// The most a share's VP9 needs at 60 fps, by height, in Mbps. 1080p is
  /// the 10 a share always started at.
  static const _vp9At60 = {
    360: 1,
    480: 2,
    720: 5,
    1080: 10,
    1440: 15,
    2160: 25,
  };

  /// What the other codecs need for the same picture. H264 needs about half
  /// as much again as VP9, measured on constrained baseline, which a phone
  /// and a browser still send. VP8 a little less than that.
  static double _codecFactor(VideoCodec codec) => switch (codec) {
    VideoCodec.vp9 => 1.0,
    VideoCodec.vp8 => 1.3,
    VideoCodec.h264 => 1.5,
  };

  /// What a desktop's H264 needs in place of [_codecFactor]'s: it goes out in
  /// High profile (`SEND_H264_HIGH` in the Rust encoder), and 12 Mbps of that
  /// at 1080p60 matched 15 of baseline on game footage (`CALLS.md`, "H264 in
  /// High profile").
  static const _h264HighFactor = 1.2;

  /// Fewer frames need fewer bits, though not in proportion: each one still
  /// has to be sharp. More need more for the same reason, though less than
  /// twice: at 120 each frame differs less from the last.
  static double _fpsFactor(int fps) => fps > 60
      ? 1.5
      : fps >= 60
      ? 1.0
      : fps >= 30
      ? 0.7
      : 0.5;

  /// The bitrate cap Auto sets, in Mbps.
  ///
  /// It is only a cap: WebRTC follows the connection under it, and a still
  /// screen sends far less. So it is what the picture needs, with no ceiling
  /// of its own; a server that wants one sets its share limit.
  ///
  /// [h264High] is whether this computer's H264 goes out in High profile.
  static int autoMbps({
    required int resolution,
    required int fps,
    required VideoCodec codec,
    bool h264High = false,
  }) {
    final base = _vp9At60[resolution] ?? _nearestBase(resolution);
    final factor = codec == VideoCodec.h264 && h264High
        ? _h264HighFactor
        : _codecFactor(codec);
    final mbps = base * _fpsFactor(fps) * factor;
    return max(1, mbps.round());
  }

  /// A height not in the table, scaled by its pixels from 1080p.
  static int _nearestBase(int resolution) {
    final scale = (resolution * resolution) / (1080 * 1080);
    return (_vp9At60[1080]! * scale).round();
  }
}
