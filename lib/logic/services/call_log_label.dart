import '../../data/classes/dm_call.dart';
import '../../data/enums/dm_call_outcome.dart';

/// How one call reads in the conversation it belongs to.
enum CallLogKind { answered, missed, declined, ongoing }

/// The line a call leaves in its conversation: "Missed call from Ben", "Call ·
/// 12 min". Pure, and apart from the row that draws it, because who is
/// reading changes the words — the same missed call is "Ben didn't answer" to
/// the person who rang.
class CallLogLabel {
  const CallLogLabel._();

  /// The line for [call] as [myId] reads it, or null for a call not worth a
  /// line: one the caller gave up on at once is nothing to the person rung,
  /// who never had a chance to answer — the server records it as cancelled
  /// for exactly that reason.
  static ({String text, CallLogKind kind})? of(
    DmCall call, {
    required String myId,
  }) {
    final incoming = call.isIncomingFor(myId);
    final peer = call.peerName;
    if (!call.isEnded) {
      return call.isAnswered
          ? (text: 'Call in progress', kind: CallLogKind.ongoing)
          : null;
    }
    return switch (call.outcome) {
      DmCallOutcome.completed => (
        text: 'Call · ${duration(call.duration ?? Duration.zero)}',
        kind: CallLogKind.answered,
      ),
      DmCallOutcome.missed => (
        text: incoming ? 'Missed call from $peer' : '$peer didn\'t answer',
        kind: CallLogKind.missed,
      ),
      DmCallOutcome.declined => (
        text: incoming
            ? 'You declined a call from $peer'
            : '$peer declined your call',
        kind: CallLogKind.declined,
      ),
      DmCallOutcome.cancelled when !incoming => (
        text: 'You cancelled a call',
        kind: CallLogKind.declined,
      ),
      _ => null,
    };
  }

  /// "under a minute", "12 min", "1 h 5 min" — how long a call ran, to the
  /// minute, because nobody reading a conversation wants the seconds.
  static String duration(Duration length) {
    final minutes = length.inMinutes;
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }
}
