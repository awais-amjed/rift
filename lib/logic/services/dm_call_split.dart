import 'dart:math' as math;

import '../../data/constants.dart';

/// Where the line between a DM call and its messages falls.
///
/// Pure, because the rules are about a window nobody has seen yet: the share
/// is stored as the user left it and applied to whatever height the pane has
/// now, so a split dragged in a tall window must still leave a short one with
/// a readable call and a composer.
class DmCallSplit {
  const DmCallSplit._();

  /// The call's height in a pane [available] tall, at [share] of it.
  ///
  /// Never under [K.dmCallStageMin], and never so tall that the messages
  /// get less than [K.dmCallChatMin] — unless the pane cannot hold both, when
  /// the call keeps its minimum and the messages take what is left.
  static double heightFor(double available, double share) {
    if (!available.isFinite || available <= 0) return K.dmCallStageMin;
    final wanted = available * (share.isFinite ? share : K.dmCallStageShare);
    final ceiling = math.max(K.dmCallStageMin, available - K.dmCallChatMin);
    return wanted.clamp(K.dmCallStageMin, ceiling).toDouble();
  }

  /// The share a drag to [height] means, in a pane [available] tall — what
  /// is stored, so the next window gets the same proportion back.
  static double shareFor(double available, double height) {
    if (!available.isFinite || available <= 0) return K.dmCallStageShare;
    return (heightFor(available, height / available) / available)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
