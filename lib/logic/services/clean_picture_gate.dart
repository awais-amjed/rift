/// Decides when a watched stream's picture is safe to show.
///
/// LiveKit's Flutter SDK attaches a receiver's decryptor only after the track
/// is subscribed, by which point frames are already flowing — so the first
/// few reach the video decoder still encrypted and decode as garbage. Frames
/// decrypted after that are fine, but they build on the garbage until the
/// next keyframe replaces it. So the picture is clean at the first keyframe
/// decoded *after* decryption began, and not before.
///
/// Fed from outside: [onDecrypting] when the SDK reports the first frame it
/// decrypted, with the keyframe count at that moment, then every later count
/// through [onKeyFrames]. [giveUp] is the backstop, so a count that never
/// arrives shows a stream late rather than never.
class CleanPictureGate {
  int? _baseline;
  bool _ready = false;

  bool get ready => _ready;

  bool get isDecrypting => _baseline != null;

  void onDecrypting(int? keyFramesDecoded) {
    _baseline ??= keyFramesDecoded ?? 0;
  }

  void onKeyFrames(int? keyFramesDecoded) {
    final baseline = _baseline;
    if (baseline == null || keyFramesDecoded == null) return;
    if (keyFramesDecoded > baseline) _ready = true;
  }

  void giveUp() => _ready = true;
}
