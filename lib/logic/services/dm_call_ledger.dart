import '../../data/classes/dm_call.dart';
import '../../data/enums/dm_call_outcome.dart';

/// A call ringing this device: on which server, and when this device first
/// heard of it, by its own clock.
///
/// [seenAt] rather than the row's `started_at`, because the two come from
/// different clocks. A phone or PC whose clock ran 45 s fast saw every ring as
/// already past its window and dropped it the moment it was fetched: no card,
/// no ringtone (review, Nov 22). The server already leaves out rings past its
/// own window, so how long one has rung *here* is the only question left.
typedef RingingCall = ({String serverId, DmCall call, DateTime seenAt});

/// Folding one server's `my_dm_calls` answer into what a device knows.
///
/// Pure, so the rules can be tested without a server: which calls ring here,
/// what became of the one we are in, and which rings ended unanswered. The
/// answer is per server — every server is asked on its own doorbell — so
/// everything this device knows about *other* servers passes through
/// untouched.
class DmCallLedger {
  const DmCallLedger._();

  /// How long a ring is worth showing. The server's own window (45 s,
  /// `app.dm_call_ring_window`); past it a ring cannot be answered, and a
  /// doorbell missed on the way out must not leave one on screen for good.
  /// Counted from [RingingCall.seenAt].
  static const ringWindow = Duration(seconds: 45);

  /// What changed on [serverId], given what it just said ([fetched]).
  ///
  /// [ringing] is every call ringing this device, on every server;
  /// [activeId] the call this device is in, if it is on this server, and
  /// [settled] the calls this device has already answered, refused or hung
  /// up — an answer fetched before that press and landing after it must not
  /// bring the ring back. Returns the new ringing list, the active call's row as the
  /// server now has it (null when it said nothing about it), and the calls
  /// that were ringing here and have ended missed — the ones worth a
  /// "Missed call".
  static ({List<RingingCall> ringing, DmCall? active, List<DmCall> missed})
  apply({
    required String serverId,
    required String myId,
    required List<RingingCall> ringing,
    required String? activeId,
    required List<DmCall> fetched,
    required DateTime now,
    Set<String> settled = const {},
  }) {
    final byId = {for (final call in fetched) call.id: call};
    final seen = {
      for (final entry in ringing)
        if (entry.serverId == serverId) entry.call.id: entry.seenAt,
    };

    final next = <RingingCall>[
      for (final entry in ringing)
        if (entry.serverId != serverId) entry,
      for (final call in fetched)
        if (call.isRinging &&
            call.isIncomingFor(myId) &&
            call.id != activeId &&
            !settled.contains(call.id) &&
            now.difference(seen[call.id] ?? now) < ringWindow)
          (serverId: serverId, call: call, seenAt: seen[call.id] ?? now),
    ]..sort((a, b) => b.call.startedAt.compareTo(a.call.startedAt));

    final missed = <DmCall>[
      for (final entry in ringing)
        if (entry.serverId == serverId)
          if (byId[entry.call.id] case final now?
              when now.isEnded && now.outcome == DmCallOutcome.missed)
            now,
    ];

    return (
      ringing: next,
      active: activeId == null ? null : byId[activeId],
      missed: missed,
    );
  }

  /// Rings older than [ringWindow], dropped. Run on a timer, for the case the
  /// doorbell that would have taken them down never came.
  static List<RingingCall> expire(List<RingingCall> ringing, DateTime now) => [
    for (final entry in ringing)
      if (now.difference(entry.seenAt) < ringWindow) entry,
  ];
}
