/// What the app does with an image the on-device classifier flags.
///
/// A per-device choice, not a server rule: the classifier runs on the bytes
/// this device decrypted, and nobody else ever sees its verdict. Blur is the
/// default — the picture is one tap away rather than gone, and the person who
/// sent it is not accused of anything.
enum SensitiveContentMode {
  /// Show everything; never run the classifier.
  off,

  /// Blur a flagged image behind a cover that reveals it on tap.
  blur,

  /// Blur a flagged image with no way to reveal it here.
  hide;

  String get label => switch (this) {
    off => 'Off',
    blur => 'Blur',
    hide => 'Hide',
  };
}
