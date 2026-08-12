import 'server_limits.dart';

/// How many messages the local user has left on one chat surface today.
///
/// Two numbers that have to stay distinguishable in three states, which is why
/// this is a type rather than a pair of nullable ints on each state class:
///
///   * **no limit** — [quota] is [ServerLimits.unlimited] and [remaining] is
///     null. Nothing to show.
///   * **limited, with room** — both set, [remaining] above zero.
///   * **spent** — [remaining] at zero, which must never be confused with the
///     zero that means "unlimited". [isExhausted] is the only correct way to
///     ask, and it checks both.
class ChatQuota {
  /// Messages allowed per rolling 24h, or [ServerLimits.unlimited].
  final int quota;

  /// Messages left, or null when there is no limit to be left of.
  final int? remaining;

  const ChatQuota({this.quota = ServerLimits.unlimited, this.remaining});

  /// What a surface reports before it has asked, and what an unlimited one
  /// keeps reporting.
  static const ChatQuota unlimited = ChatQuota();

  /// True when a limit applies here at all.
  bool get isLimited => quota > ServerLimits.unlimited && remaining != null;

  /// True when the next message would be refused.
  bool get isExhausted => isLimited && remaining! <= 0;

  /// The fraction still available, for a meter. 1.0 when unlimited.
  double get fraction => isLimited ? (remaining! / quota).clamp(0.0, 1.0) : 1.0;

  /// One message spent, floored at zero.
  ///
  /// Sends decrement locally rather than re-asking the server every time: the
  /// count that matters is re-read whenever the surface is opened, and a meter
  /// that lags by one message until the next round trip is worse than one that
  /// is occasionally a message optimistic on another device.
  ChatQuota spendOne() => isLimited
      ? ChatQuota(quota: quota, remaining: remaining! > 0 ? remaining! - 1 : 0)
      : this;

  /// What the server said, as this type.
  factory ChatQuota.fromResult(({int quota, int? remaining}) result) =>
      ChatQuota(quota: result.quota, remaining: result.remaining);

  /// The state the quota wall leaves behind — the limit stands, nothing left.
  ChatQuota get spent => quota > ServerLimits.unlimited
      ? ChatQuota(quota: quota, remaining: 0)
      : this;

  @override
  bool operator ==(Object other) =>
      other is ChatQuota &&
      other.quota == quota &&
      other.remaining == remaining;

  @override
  int get hashCode => Object.hash(quota, remaining);
}
