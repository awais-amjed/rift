import 'dart:async';

import '../../data/classes/server.dart';
import 'server_realtime.dart';
import 'server_topics.dart';

/// A subscription to a server's key-sweep doorbell.
///
/// A `sweep` on the server's topic, rung whenever a client publishes a chat
/// key, heals somebody's keyring entry, or rotates a channel. It carries no
/// payload — it is a nudge to go and look, which is what keeps it cheap enough
/// to ring often.
///
/// Extracted because there are two listeners with nothing else in common: the
/// open text channel wants to re-run its sweep, and a call in progress wants to
/// know its key rotated out from under it.
class KeySweepDoorbell {
  RealtimeLease? _lease;

  /// Whether this doorbell is currently listening.
  bool get isListening => _lease != null;

  /// Listen on [server], calling [onRing] each time somebody rings.
  ///
  /// Replaces any existing subscription, so it is safe to call again on a
  /// server change without leaking the previous one. Does nothing for a server
  /// with no anon key — there is nothing to connect with, and a call or a
  /// channel that works without the doorbell is better than one that fails
  /// because of it. The chat and a call in progress each hold one of these;
  /// [realtime] gives them the same join.
  void listen(ServerRealtime realtime, Server server, void Function() onRing) {
    unawaited(stop());
    _lease = realtime.join(server, ServerTopics.server(server.id))
      ?..onBroadcast(ServerEvent.sweep, (_) => onRing());
  }

  /// Ring it, so other clients go and look — and anything else on this device
  /// listening to the same server.
  ///
  /// The second half is not a courtesy. A rotation is minted by whichever
  /// client's sweep wins the race, and when that client is also in the call,
  /// the call has to move with everyone else. It heard the server's ring (a
  /// ban) before the rotation existed, found nothing new, and would never
  /// hear this one: the socket does not echo a send to its sender.
  ///
  /// Best-effort: the thing being announced has already happened, and a
  /// doorbell nobody heard costs somebody a wait rather than correctness.
  void ring() {
    _lease
      ?..send(ServerEvent.sweep, const {})
      ..echoLocally(ServerEvent.sweep, const {});
  }

  /// Stop listening.
  ///
  /// The field is cleared before the await so a `stop` racing a `listen`
  /// cannot release the new subscription instead of the old one.
  Future<void> stop() async {
    final lease = _lease;
    _lease = null;
    await lease?.release();
  }
}
