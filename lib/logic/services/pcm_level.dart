import 'dart:math' as math;
import 'dart:typed_data';

/// Turns a frame of raw microphone PCM into the single 0–1 number that the
/// level meter and the speaking indicator share.
///
/// This replaces the audio visualizer's normalised band peak, which was a
/// display value with no defined relationship to loudness. Real audio occupied
/// only the very bottom of its 0–1 range — a quiet room read about 0.03 and
/// even a raised voice rarely passed 0.25 — so a threshold expressed in it
/// spent almost all of its travel above any human voice. Every attempt to make
/// a usable slider out of it (squeezed ranges, curves) was compensating for a
/// ruler with no marks on it.
///
/// A microphone's loudness has a standard unit: **dBFS**, the RMS amplitude of
/// the samples relative to full scale, on a log scale. It is what every meter
/// in every audio application shows, it matches how loudness is perceived, and
/// speech and silence land far apart in it. [floorDb] to 0 dBFS is mapped onto
/// 0–1 so the rest of the app keeps a plain fraction to work with, but the
/// spacing is now meaningful: a quiet room sits near the bottom, ordinary
/// speech around the middle, a shout near the top.
class PcmLevel {
  const PcmLevel._();

  /// The quietest level the meter resolves. Anything below reads as 0.
  ///
  /// -60 dBFS is far under any room tone a microphone picks up, so the bottom
  /// of the scale is genuine silence rather than a noise floor.
  static const double floorDb = -60;

  /// RMS amplitude (0–1) of one frame of interleaved signed 16-bit PCM.
  ///
  /// RMS rather than peak: a peak is a single sample and jumps around on
  /// transients, while RMS is the frame's actual energy, which is what
  /// loudness means. Channels are averaged together — this is a level, not a
  /// mix.
  static double rms(Uint8List bytes) {
    final samples = _asInt16(bytes);
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in samples) {
      final normalized = sample / 32768.0;
      sum += normalized * normalized;
    }
    return math.sqrt(sum / samples.length);
  }

  /// RMS amplitude → dBFS, bottoming out at [floorDb] so digital silence is a
  /// number rather than negative infinity.
  static double toDb(double rms) {
    if (rms <= 0) return floorDb;
    final db = 20 * (math.log(rms) / math.ln10);
    return db.clamp(floorDb, 0.0);
  }

  /// dBFS → the 0–1 scale the meter, the gate and the speaking indicator all
  /// speak. Linear in decibels, so equal slider movement is equal loudness
  /// change wherever you are on it.
  static double normalize(double db) =>
      ((db - floorDb) / -floorDb).clamp(0.0, 1.0);

  /// One frame of interleaved signed 16-bit PCM → the shared 0–1 level.
  static double fromInt16(Uint8List bytes) => normalize(toDb(rms(bytes)));

  /// Views [bytes] as 16-bit samples without copying where the platform
  /// channel handed us an aligned buffer, which is the normal case. A view
  /// needs an even byte offset, so the rare misaligned frame is copied rather
  /// than throwing.
  static Int16List _asInt16(Uint8List bytes) {
    final sampleCount = bytes.lengthInBytes ~/ 2;
    if (sampleCount == 0) return Int16List(0);
    if (bytes.offsetInBytes.isEven) {
      return bytes.buffer.asInt16List(bytes.offsetInBytes, sampleCount);
    }
    return Uint8List.fromList(bytes).buffer.asInt16List(0, sampleCount);
  }
}
