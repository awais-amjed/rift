import 'dart:async';

import '../../data/classes/share_ladder.dart';
import '../../src/rust/api/screenshare/types.dart';

/// Keeps a running share on the rung its watchers need ([ShareLadder]).
///
/// Down at once: somebody is looking at a picture they cannot play. Back up
/// only once nobody has needed the lower rung for [climbAfter], since every
/// move blinks the picture for everyone, and people open and close a stream.
class ShareRungFollow {
  static const climbAfter = Duration(seconds: 30);

  final void Function(VideoCodec rung) onMove;

  Timer? _climb;
  VideoCodec? _wanted;

  ShareRungFollow({required this.onMove});

  /// Whether a climb is waiting out [climbAfter].
  bool get climbing => _climb != null;

  /// Where the share stands now: called with each change to any of these.
  void update({
    required VideoCodec top,
    required VideoCodec current,
    required Iterable<ShareWatcher> watchers,
  }) {
    final wanted = ShareLadder.rungFor(top: top, watchers: watchers);
    _wanted = wanted;
    if (wanted == current) return cancel();
    if (ShareLadder.isBelow(wanted, current)) {
      cancel();
      return onMove(wanted);
    }
    _climb ??= Timer(climbAfter, () {
      _climb = null;
      onMove(_wanted!);
    });
  }

  void cancel() {
    _climb?.cancel();
    _climb = null;
  }
}
