import 'dart:async';

import '../../data/repositories/session_repository.dart';
import 'server_context.dart';

/// The live [ServerContext]s, one per server something holds, and nothing
/// for a server nothing holds.
///
/// Holds two itself — the selected server's and the call's, which need not
/// be the same — so the selected server's badge and doorbell run whatever is
/// on screen, and a call keeps its server's presence and roster while its
/// member reads another. A page about some other server takes a [hold] of its
/// own (`ServerContextScope`) for as long as it is open. The last hold let go
/// shuts that server's context down at once: its joins left, its watchers
/// stopped, nobody there told we are about.
class ServerHub {
  final SessionRepository _session;
  final ServerContext Function(String serverId) _open;

  final Map<String, ({ServerContext context, int holds})> _live = {};
  ServerContext? _none;
  ServerHold? _selected;
  ServerHold? _call;
  StreamSubscription<void>? _selectionSub;
  StreamSubscription<void>? _callSub;
  bool _disposed = false;

  /// [open] builds a server's context the first time something holds it.
  ServerHub({
    required SessionRepository session,
    required ServerContext Function(String serverId) open,
  }) : _session = session,
       _open = open {
    _selectionSub = session.changes.listen((_) => _follow());
    _callSub = session.callChanges.listen((_) => _follow());
    _follow();
  }

  /// [serverId]'s context while something holds it. Never opens one: what
  /// asks this way is answered about a server already in use, or not at all.
  ServerContext? operator [](String? serverId) => _live[serverId]?.context;

  /// The context of no server: what the screen reads before one is chosen,
  /// since the channel list and the call's pane are drawn with or without
  /// one. Every list in it is empty and it joins nothing, because no server's
  /// id is empty. Built on first use and kept until the hub goes.
  ServerContext get none => _none ??= _open('');

  /// Keep [serverId]'s context alive, opening it if nothing else holds it,
  /// until the hold is let go.
  ServerHold hold(String serverId) {
    final live = _live[serverId];
    final context = live?.context ?? _open(serverId);
    _live[serverId] = (context: context, holds: (live?.holds ?? 0) + 1);
    return ServerHold._(this, context);
  }

  void _release(String serverId) {
    final live = _live[serverId];
    if (live == null) return;
    if (live.holds > 1) {
      _live[serverId] = (context: live.context, holds: live.holds - 1);
      return;
    }
    _live.remove(serverId);
    unawaited(live.context.close());
  }

  void _follow() {
    if (_disposed) return;
    _selected = _move(_selected, _session.selectedServerId);
    _call = _move(_call, _session.callServerId);
  }

  /// [held] moved to [serverId]: the new one taken before the old one goes,
  /// so a context both point at is never shut and opened again.
  ServerHold? _move(ServerHold? held, String? serverId) {
    if (held?.context.serverId == serverId) return held;
    final next = serverId == null ? null : hold(serverId);
    held?.release();
    return next;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _selectionSub?.cancel();
    await _callSub?.cancel();
    final live = [for (final entry in _live.values) entry.context, ?_none];
    _live.clear();
    for (final context in live) {
      await context.close();
    }
  }
}

/// One use of a server's context. Let go exactly once.
class ServerHold {
  final ServerHub _hub;
  final ServerContext context;
  bool _released = false;

  ServerHold._(this._hub, this.context);

  void release() {
    if (_released) return;
    _released = true;
    _hub._release(context.serverId);
  }
}
