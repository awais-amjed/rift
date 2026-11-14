import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../../data/classes/attachment.dart';
import '../../../../../data/enums/sensitive_content_mode.dart';
import '../../../../../logic/services/chat_clip/chat_clip.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/image_safety.dart';
import '../../../../../logic/services/image_safety_classifier.dart';
import '../sensitive_image_cover.dart';

/// Whether a chat video may be shown, by the same on-device model as a
/// picture: its poster is looked at before it is drawn, and while it plays
/// the picture showing is looked at once every [every]. A flagged one is
/// paused and covered, as a flagged picture is.
///
/// While it plays, not before: not a byte of a video is fetched until play
/// is pressed, so the poster is all there is to look at until then. A
/// picture every second or two rather than every one, since what a video
/// shows does not change from one frame to the next: a look took about 40 ms
/// on a laptop's CPU and 170 ms on a mid-range phone (Nov 14).
///
/// The verdict is kept under the video's id ([ImageSafetyClassifier.remember]),
/// so a card scrolled away and back is covered at once.
class ClipSafety {
  final Attachment attachment;

  /// The setting, read when the card was made, as a picture's thumbnail
  /// reads it.
  final SensitiveContentMode mode;

  final VoidCallback _changed;

  /// Told when a picture is flagged while it plays: the playback pauses.
  final VoidCallback _flagged;

  ClipSafety({
    required this.attachment,
    required this.mode,
    required VoidCallback changed,
    required VoidCallback flagged,
  }) : _changed = changed,
       _flagged = flagged,
       sensitive =
           ImageSafetyClassifier.instance.cached(attachment.id)?.isSensitive ??
           false;

  /// How often a playing video is looked at: half as often on a phone,
  /// where a look costs four times as much and the battery pays for it.
  static Duration get every => HostPlatform.isMobile
      ? const Duration(seconds: 2)
      : const Duration(seconds: 1);

  /// Something in it was flagged: the poster, or a picture while it played.
  bool sensitive;

  /// The poster has been looked at, or needs no look, and may be drawn.
  bool posterChecked = false;

  Uint8List? _poster;
  Timer? _looks;
  bool _looking = false;
  bool _gone = false;

  bool get _watching => mode != SensitiveContentMode.off && !sensitive;

  /// Flagged and not lifted: drawn behind the cover, and it does not play.
  bool get covered =>
      sensitive &&
      mode != SensitiveContentMode.off &&
      !SensitiveImageCover.isRevealed(attachment.id);

  /// The poster's [bytes], looked at once for each new set. Called as the
  /// card draws, so it only starts the look; the answer comes as a change.
  void lookAtPoster(Uint8List bytes) {
    if (identical(bytes, _poster)) return;
    _poster = bytes;
    final poster = attachment.poster;
    if (!_watching || poster == null) {
      posterChecked = true;
      return;
    }
    final classifier = ImageSafetyClassifier.instance;
    final known = classifier.cached(poster.id);
    if (known != null) {
      if (known.isSensitive) _flag(known);
      posterChecked = true;
      return;
    }
    unawaited(
      classifier.classify(poster.id, bytes).then((verdict) {
        if (_gone) return;
        if (verdict != null && verdict.isSensitive) _flag(verdict);
        posterChecked = true;
        _changed();
      }),
    );
  }

  /// Looks at [clip] every so often while it plays.
  void watch(ChatClip clip) {
    stop();
    if (!_watching) return;
    _looks = Timer.periodic(every, (_) => unawaited(_look(clip)));
  }

  void stop() {
    _looks?.cancel();
    _looks = null;
  }

  void dispose() {
    _gone = true;
    stop();
  }

  /// One look, never two at once: a slow phone skips a beat rather than
  /// queueing them.
  Future<void> _look(ChatClip clip) async {
    if (_looking || !_watching) return;
    _looking = true;
    try {
      final rgba = await clip.frame(ImageSafetyClassifier.side);
      if (rgba == null || _gone || _blank(rgba)) return;
      final verdict = await ImageSafetyClassifier.instance.classifyFrame(rgba);
      if (verdict == null || !verdict.isSensitive || _gone) return;
      _flag(verdict);
      stop();
      _flagged();
      _changed();
    } finally {
      _looking = false;
    }
  }

  /// Nothing drawn yet: a texture reads black until its first picture
  /// lands, and black would pass as safe. A video that really is black there
  /// loses nothing by being skipped.
  static bool _blank(ByteData rgba) {
    for (var i = 0; i < rgba.lengthInBytes; i += 4) {
      if (rgba.getUint8(i) | rgba.getUint8(i + 1) | rgba.getUint8(i + 2) != 0) {
        return false;
      }
    }
    return true;
  }

  void _flag(ImageSafetyVerdict verdict) {
    sensitive = true;
    ImageSafetyClassifier.instance.remember(attachment.id, verdict);
  }
}
