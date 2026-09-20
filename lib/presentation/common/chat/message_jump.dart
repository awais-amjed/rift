import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/app_motion.dart';

/// Taking the reader to a message that is already loaded.
///
/// **Only a message already in the list**, which is not a limitation so much
/// as the shape of the feature: a reply quote resolves against the loaded
/// page and draws "original unavailable" when it cannot, so by the time
/// there is something to press there is something to scroll to. Nothing here
/// fetches history.
///
/// The awkward part is that a `ListView.builder` builds what is near the
/// viewport and nothing else, so the row being scrolled *to* usually does
/// not exist yet. [Scrollable.ensureVisible] needs a built context, so this
/// converges instead: guess where the row is from its place in the list,
/// jump there, and look again. Rows vary in height — an image is twenty
/// times a one-line message — so the first guess is rough and the second is
/// close, which is why the loop exists and why it is capped rather than
/// while-true.
class MessageJumper {
  /// One key per row, kept for as long as the conversation is open.
  ///
  /// Allocated here rather than derived from the id, because two chat
  /// surfaces can be mounted at once and their ids are both plain serials —
  /// message 42 exists in a channel and in a DM. Keys made from the id would
  /// be the same key twice and Flutter would refuse to build. These are
  /// distinct objects per list, so they cannot collide however the ids fall.
  final Map<String, GlobalKey> _keys = {};

  /// How many times to guess before giving up. Three is enough for a list of
  /// a few thousand; the cap is here so a list that reflows under the jump
  /// cannot spin.
  static const int _attempts = 4;

  GlobalKey keyFor(String rowId) =>
      _keys.putIfAbsent(rowId, () => GlobalKey(debugLabel: 'msg:$rowId'));

  /// Drop keys for rows that are gone, so a long-lived conversation does not
  /// accumulate one per message ever seen.
  void keepOnly(Set<String> rowIds) =>
      _keys.removeWhere((id, _) => !rowIds.contains(id));

  /// Scroll [rowId] into view. Answers whether it got there, so the caller
  /// only marks the row when the reader is actually looking at it.
  ///
  /// [fractionOf] answers where the row sits in the list as 0 (the end the
  /// scroll starts at) to 1 (the far end), or null if it is not there.
  Future<bool> jumpTo(
    String rowId, {
    required ScrollController? controller,
    required double? Function(String rowId) fractionOf,
  }) async {
    if (controller == null || !controller.hasClients) return false;

    for (var attempt = 0; attempt < _attempts; attempt++) {
      if (await _reveal(rowId)) return true;

      final fraction = fractionOf(rowId);
      if (fraction == null) return false;

      final position = controller.position;
      final target = (fraction * position.maxScrollExtent).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      // Jumped, not animated. This is a guess that is about to be corrected,
      // and animating a guess shows the reader a scroll to the wrong place
      // followed by a second one to the right place.
      if ((target - position.pixels).abs() < 1) break;
      controller.jumpTo(target);
      await SchedulerBinding.instance.endOfFrame;
    }
    return _reveal(rowId);
  }

  /// Bring the row in if it has been built. The animation is [AppMotion.state]
  /// because by here the page is already at the right place and this is the
  /// last few hundred pixels — a long travel would be the reader waiting.
  Future<bool> _reveal(String rowId) async {
    final context = _keys[rowId]?.currentContext;
    if (context == null) return false;
    await Scrollable.ensureVisible(
      context,
      // Not centred: a reply is usually just above what you were reading,
      // and putting it dead centre throws away the messages after it, which
      // are the ones that explain why you were sent here.
      alignment: 0.35,
      duration: AppMotion.state,
      curve: AppMotion.settle,
    );
    return true;
  }
}
