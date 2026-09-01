import 'dart:async';

import 'package:supabase/supabase.dart';

import '../../data/classes/server.dart';

/// A subscription to a server's key-sweep doorbell.
///
/// One broadcast topic, `keysweep:<serverId>`, rung whenever a client publishes
/// a chat key, heals somebody's keyring entry, or rotates a channel. It carries
/// no payload — it is a nudge to go and look, which is what keeps it cheap
/// enough to ring often.
///
/// Extracted because there are two listeners with nothing else in common: the
/// open text channel wants to re-run its sweep, and a call in progress wants to
/// know its key rotated out from under it. Both were opening a client,
/// subscribing, and tearing the pair down in the same slightly fiddly order,
/// and the second copy of that is the warning.
class KeySweepDoorbell {
  SupabaseClient? _client;
  RealtimeChannel? _channel;

  /// Whether this doorbell is currently listening.
  bool get isListening => _channel != null;

  /// Listen on [server], calling [onRing] each time somebody rings.
  ///
  /// Replaces any existing subscription, so it is safe to call again on a
  /// server change without leaking the previous one. Does nothing for a server
  /// with no anon key — there is nothing to connect with, and a call or a
  /// channel that works without the doorbell is better than one that fails
  /// because of it.
  void listen(Server server, void Function() onRing) {
    stop();
    final anonKey = server.supabaseKey;
    if (anonKey == null) return;
    _client = SupabaseClient(server.supabaseUrl, anonKey);
    _channel = _client!.channel('keysweep:${server.id}')
      ..onBroadcast(event: 'sweep', callback: (_) => onRing())
      ..subscribe();
  }

  /// Ring it, so other clients go and look.
  ///
  /// Best-effort: the thing being announced has already happened, and a
  /// doorbell nobody heard costs somebody a wait rather than correctness.
  void ring() {
    try {
      _channel?.sendBroadcastMessage(event: 'sweep', payload: {});
    } catch (_) {}
  }

  /// Stop listening and dispose the client.
  ///
  /// The fields are cleared before the awaits so a `stop` racing a `listen`
  /// cannot tear down the new subscription instead of the old one.
  Future<void> stop() async {
    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    try {
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
  }
}
