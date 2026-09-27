import '../../data/classes/dm_call.dart';
import '../../data/enums/dm_call_outcome.dart';

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
  static const ringWindow = Duration(seconds: 45);

  /// What changed on [serverId], given what it just said ([fetched]).
  ///
  /// [ringing] is every call ringing this device, on every server, as
  /// `(serverId, call)`; [activeId] the call this device is in, if it is on
  /// this server. Returns the new ringing list, the active call's row as the
  /// server now has it (null when it said nothing about it), and the calls
  /// that were ringing here and have ended missed — the ones worth a
  /// "Missed call".
  static ({
    List<({String serverId, DmCall call})> ringing,
    DmCall? active,
    List<DmCall> missed,
  })
  apply({
    required String serverId,
    required String myId,
    required List<({String serverId, DmCall call})> ringing,
    required String? activeId,
    required List<DmCall> fetched,
    required DateTime now,
  }) {
    final byId = {for (final call in fetched) call.id: call};

    final next = <({String serverId, DmCall call})>[
      for (final entry in ringing)
        if (entry.serverId != serverId) entry,
      for (final call in fetched)
        if (call.isRinging &&
            call.isIncomingFor(myId) &&
            call.id != activeId &&
            now.difference(call.startedAt) < ringWindow)
          (serverId: serverId, call: call),
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
  static List<({String serverId, DmCall call})> expire(
    List<({String serverId, DmCall call})> ringing,
    DateTime now,
  ) => [
    for (final entry in ringing)
      if (now.difference(entry.call.startedAt) < ringWindow) entry,
  ];
}
