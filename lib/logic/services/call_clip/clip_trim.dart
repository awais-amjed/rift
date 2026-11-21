import 'dart:typed_data';

/// The trim view's arithmetic over a clip (CALLS.md, "Clipping a call"):
/// interleaved 16-bit frames, 48 kHz unless said otherwise.
abstract final class ClipTrim {
  static const int rate = 48000;

  /// The frames from [start] to [end], each kept within the clip. Nothing
  /// when [start] is not before [end].
  static Int16List cut(
    Int16List pcm,
    int channels,
    Duration start,
    Duration end, {
    int rate = rate,
  }) {
    final frames = pcm.length ~/ channels;
    int at(Duration d) =>
        (d.inMicroseconds * rate / Duration.microsecondsPerSecond)
            .round()
            .clamp(0, frames);
    final from = at(start);
    final to = at(end);
    if (from >= to) return Int16List(0);
    return pcm.sublist(from * channels, to * channels);
  }

  /// The loudest sample of each of [buckets] even stretches of [pcm], any
  /// channel, from 0 (silence) to 1 (full scale): the waveform's bars.
  static List<double> peaks(Int16List pcm, int channels, int buckets) {
    if (buckets <= 0) return const [];
    final frames = pcm.length ~/ channels;
    final out = List<double>.filled(buckets, 0);
    if (frames == 0) return out;
    for (var b = 0; b < buckets; b++) {
      final from = b * frames ~/ buckets * channels;
      final to = (b + 1) * frames ~/ buckets * channels;
      var loudest = 0;
      for (var i = from; i < to; i++) {
        final v = pcm[i];
        final a = v < 0 ? -v : v;
        if (a > loudest) loudest = a;
      }
      out[b] = loudest >= 32768 ? 1.0 : loudest / 32768;
    }
    return out;
  }

  /// What [d] of the clip comes to as a WAV: its 44-byte header, then four
  /// bytes a frame (stereo, 16-bit).
  static int wavBytes(Duration d) =>
      44 + d.inMicroseconds * rate ~/ Duration.microsecondsPerSecond * 4;

  /// What [d] comes to as a constant-rate MP3 at [kbps].
  static int mp3Bytes(Duration d, int kbps) =>
      d.inMicroseconds * kbps * 1000 ~/ 8 ~/ Duration.microsecondsPerSecond;

  /// Where the play line is, as a fraction of the clip: [elapsed] into a
  /// preview of the selection from [start] to [end] (fractions too), which
  /// lasts [length]. Held at [end] once it is over, since the timer that
  /// asks can be late.
  static double playhead({
    required double start,
    required double end,
    required Duration elapsed,
    required Duration length,
  }) {
    if (length <= Duration.zero) return start;
    final played = elapsed.inMicroseconds / length.inMicroseconds;
    return start + (end - start) * played.clamp(0.0, 1.0);
  }

  /// `m:ss.t`, for the ends of the selection.
  static String timeLabel(Duration d) {
    final tenths = d.inMilliseconds ~/ 100;
    final seconds = tenths ~/ 10;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
        '.${tenths % 10}';
  }

  /// `rift-clip-<yyyyMMdd-HHmmss>.<extension>`, from when it was clipped.
  static String fileName(DateTime at, String extension) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'rift-clip-${at.year}${two(at.month)}${two(at.day)}-'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}.$extension';
  }
}
