/// Decides whether someone is speaking from a stream of microphone levels.
///
/// The speaking glow used to come only from LiveKit's server-side active
/// speaker detection, which is deliberately conservative — it reports the
/// loudest few participants on a fixed interval, so normal-volume speech often
/// never lit the indicator. For the local user we have the mic level right
/// here, so this decides locally and immediately.
///
/// Fast attack (speech shows on the first loud sample) and a hold on release
/// (the indicator doesn't strobe between words).
class SpeechDetector {
  /// Level at or above which speech starts. The audio visualizer reports a
  /// normalised 0–1 band peak; a quiet room sits well under this, while
  /// conversational speech runs several times higher.
  static const double defaultThreshold = 0.07;

  /// Keep reporting speech this long after the level drops.
  static const Duration defaultHold = Duration(milliseconds: 400);

  final double threshold;
  final Duration hold;

  bool _speaking = false;
  DateTime? _holdUntil;

  SpeechDetector({this.threshold = defaultThreshold, this.hold = defaultHold});

  bool get isSpeaking => _speaking;

  /// Feeds one level sample. Returns true when [isSpeaking] flipped, so the
  /// caller only pushes a UI update on a real transition.
  bool update(double level, DateTime now) {
    if (level >= threshold) {
      _holdUntil = now.add(hold);
      return _set(true);
    }
    // Below the threshold, but still inside the hold window.
    if (_holdUntil != null && now.isBefore(_holdUntil!)) return false;
    return _set(false);
  }

  /// Forces silence — the mic went away, was muted, or the call ended.
  /// Returns true when that was a change.
  bool reset() {
    _holdUntil = null;
    return _set(false);
  }

  bool _set(bool value) {
    if (_speaking == value) return false;
    _speaking = value;
    return true;
  }
}
