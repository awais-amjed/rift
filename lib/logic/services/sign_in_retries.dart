import 'dart:async';

import 'package:flutter/foundation.dart';

/// Which servers keep refusing to sign us in, when to try each again, and
/// which ones we have stopped trying until somebody opens them.
///
/// A sign-in fails for reasons the app cannot tell apart: the server is off,
/// the network is, or the server was reinstalled and no longer takes the key
/// we hold for it. None of those is a reason to forget the server — only the
/// server itself saying it does not know us is (`ServerDb.serverGone`) — and
/// none is helped by asking again every time the server list ticks, which is
/// what the background refresh did: a reinstalled server was signed in to
/// over and over while its sidebar waited on a token that never came.
///
/// So a failure is tried again a few times, further apart each time, and then
/// only every [slowRetry]: the server is reported out of reach ([givenUp]) the
/// way a server whose socket is down is. Opening it tries at once (an `asked`
/// failure is out of reach at once, since somebody is waiting on the answer),
/// and so does its socket coming back.
///
/// Never stopped for good. A server given up on whose socket never connected
/// has no socket to come back: a launch before the network was up, on a token
/// already expired, held its join back and stayed "can't reach" until the
/// server was opened or the app restarted, however long the network had been
/// back.
class SignInRetries {
  /// The waits before each try after the first: five tries in all, the last
  /// a little over three minutes after the first.
  static const List<Duration> delays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
  ];

  /// How often a server given up on is tried after that.
  static const Duration slowRetry = Duration(minutes: 5);

  final void Function(String serverId) _retry;
  final ValueListenable<Set<String>> _sockets;
  final Map<String, ({int failures, Timer? timer})> _failing = {};
  final ValueNotifier<Set<String>> _givenUp = ValueNotifier(const {});
  final ValueNotifier<Set<String>> _outOfReach = ValueNotifier(const {});
  Set<String> _socketsDown = const {};

  /// [retry] signs in to a server again; [sockets] are the servers whose
  /// Realtime socket is down, one coming back being a reason to try again.
  SignInRetries({
    required void Function(String serverId) retry,
    required ValueListenable<Set<String>> sockets,
  }) : _retry = retry,
       _sockets = sockets {
    _socketsDown = sockets.value;
    _outOfReach.value = _socketsDown;
    sockets.addListener(_onSockets);
  }

  /// The servers we have stopped trying to sign in to.
  ValueListenable<Set<String>> get givenUp => _givenUp;

  /// The servers that cannot be reached: their socket is down, or we have
  /// stopped trying to sign in to them. What the title bar and the sidebars
  /// say "can't reach" about, rather than drawing an answer as coming.
  ValueListenable<Set<String>> get outOfReach => _outOfReach;

  /// Whether a sign-in to [serverId] should wait: a retry is already timed,
  /// or we have stopped trying. What asks in the background — a token near
  /// its end, a refused join — is told no rather than trying again early.
  bool holdsBack(String serverId) {
    final failing = _failing[serverId];
    if (failing == null) return false;
    return failing.timer?.isActive ?? true;
  }

  /// A sign-in to [serverId] worked.
  void succeeded(String serverId) => forget(serverId);

  /// A sign-in to [serverId] failed. [asked] is a server somebody opened.
  void failed(String serverId, {bool asked = false}) {
    final previous = _failing.remove(serverId);
    previous?.timer?.cancel();
    final failures = (previous?.failures ?? 0) + 1;
    final wait = failures <= delays.length ? delays[failures - 1] : slowRetry;
    _failing[serverId] = (
      failures: failures,
      timer: Timer(wait, () => _retry(serverId)),
    );
    if (asked || failures > delays.length) {
      _setGivenUp({..._givenUp.value, serverId});
    }
  }

  /// Forget every server but [serverIds], the list as it now stands. A server
  /// left and joined again in one session started out given up on.
  void keepOnly(Set<String> serverIds) {
    for (final serverId in _failing.keys.toList()) {
      if (!serverIds.contains(serverId)) forget(serverId);
    }
    final stale = _givenUp.value.difference(serverIds);
    if (stale.isNotEmpty) _setGivenUp(_givenUp.value.difference(stale));
  }

  /// Nothing more to try for [serverId]: it signed in, or it is gone.
  void forget(String serverId) {
    _failing.remove(serverId)?.timer?.cancel();
    if (_givenUp.value.contains(serverId)) {
      _setGivenUp({..._givenUp.value}..remove(serverId));
    }
  }

  void _onSockets() {
    final down = _sockets.value;
    final back = _socketsDown.difference(down);
    _socketsDown = down;
    _updateOutOfReach();
    for (final serverId in back) {
      if (!_failing.containsKey(serverId)) continue;
      forget(serverId);
      _retry(serverId);
    }
  }

  void _setGivenUp(Set<String> servers) {
    _givenUp.value = Set.unmodifiable(servers);
    _updateOutOfReach();
  }

  void _updateOutOfReach() {
    final both = {..._socketsDown, ..._givenUp.value};
    if (setEquals(both, _outOfReach.value)) return;
    _outOfReach.value = Set.unmodifiable(both);
  }

  void dispose() {
    _sockets.removeListener(_onSockets);
    for (final failing in _failing.values) {
      failing.timer?.cancel();
    }
    _failing.clear();
    _givenUp.dispose();
    _outOfReach.dispose();
  }
}
