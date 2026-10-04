import 'dart:convert';

import 'video_stream_stats.dart';

/// The state a client publishes about itself into a call.
///
/// LiveKit tells the room about tracks, not about intentions. A muted
/// microphone is visible because the track goes away; deafening is a decision
/// made entirely inside the listener's client — it unsubscribes from other
/// people's audio, which nobody else can see. So it is said out loud, as a
/// participant attribute, and everyone's roster can show it. Watching a stream
/// is the same: a subscription only the watcher's client knows about.
///
/// Attributes are plain strings, and an attribute that has never been set is
/// simply absent — so reading is written to accept anything and answer no.
class VoiceAttributes {
  const VoiceAttributes._();

  static const deafenedKey = 'deafened';

  /// The streams this client is watching, as a JSON list of share identities.
  static const watchingKey = 'watching';

  /// What to publish for a client that is (or is not) deafened, watching
  /// [watching]. Watching is always sent, even empty, so that the first value
  /// anyone sees is a baseline rather than a change — see `watchCues`.
  static Map<String, String> forSelf({
    required bool deafened,
    required Set<String> watching,
  }) => {
    deafenedKey: deafened ? 'true' : 'false',
    watchingKey: jsonEncode(watching.toList()..sort()),
  };

  static bool isDeafened(Map<String, String> attributes) =>
      attributes[deafenedKey] == 'true';

  /// Set by a desktop screen share's own connection, not by [forSelf]: the
  /// Rust session publishes it while the shared window is minimised, when
  /// Windows hands the capturer nothing new and viewers would otherwise be
  /// left looking at a frozen picture with no idea why.
  static const sharePausedKey = 'paused';

  static bool isSharePaused(Map<String, String> attributes) =>
      attributes[sharePausedKey] == 'true';

  /// Set by a desktop screen share's own connection each time it publishes its
  /// picture: the size it sends (`1920x1080`) and the rate it was asked for.
  /// Viewers show these rather than the rate they measure, which falls
  /// whenever the shared screen stands still and so reads as the share
  /// flickering between 30 and 60.
  static const shareSizeKey = 'size';
  static const shareFpsKey = 'fps';

  /// What a share says it is sending, or null when it has not said (a phone's
  /// share, or a client from before this was published).
  static VideoStreamStats? sentPictureOf(Map<String, String> attributes) {
    final size = attributes[shareSizeKey]?.split('x');
    if (size == null || size.length != 2) return null;
    final width = int.tryParse(size[0]);
    final height = int.tryParse(size[1]);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return VideoStreamStats(
      width: width,
      height: height,
      fps: double.tryParse(attributes[shareFpsKey] ?? ''),
    );
  }

  /// The streams [attributes] says are being watched; empty for anything
  /// unreadable.
  static Set<String> watchingOf(Map<String, String> attributes) {
    final raw = attributes[watchingKey];
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return decoded.whereType<String>().toSet();
    } on FormatException {
      return const {};
    }
  }
}
