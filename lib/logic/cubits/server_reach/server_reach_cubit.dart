import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../server/server_cubit.dart';

part 'server_reach_state.dart';

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Says when the selected server can't be reached, for the title bar.
///
/// Only the selected one: a server you are not looking at being down is
/// nothing to act on, and its unread badges simply stop moving. The signal is
/// the server's realtime socket ([ServerRealtime.unreachable]) — the one
/// connection every joined server keeps open.
class ServerReachCubit extends Cubit<ServerReachState> {
  /// How long a server has to stay out of reach before it is reported. A
  /// socket that drops reconnects in a second or two, and a red chip blinking
  /// through that would be crying wolf; coming back is reported at once. A
  /// server switched to that has been down for longer shows straight away.
  static const settle = Duration(seconds: 5);

  final ValueListenable<Set<String>> _unreachable;
  final Duration _settle;
  final Map<String, DateTime> _downSince = {};
  StreamSubscription<({String id, String name})?>? _selectedSub;
  ({String id, String name})? _selected;
  Timer? _timer;

  ServerReachCubit({
    required ValueListenable<Set<String>> unreachable,
    required Stream<({String id, String name})?> selected,
    ({String id, String name})? initial,
    Duration settle = settle,
  }) : _unreachable = unreachable,
       _settle = settle,
       _selected = initial,
       super(const ServerReachState()) {
    _unreachable.addListener(_onUnreachable);
    _selectedSub = selected.listen((server) {
      _selected = server;
      _evaluate();
    });
    _onUnreachable();
  }

  /// Wired to a [ServerCubit]: its sockets, and its selected server.
  factory ServerReachCubit.of(ServerCubit servers) {
    ({String id, String name})? selectedOf(ServerState state) {
      final server = state.selectedServer;
      return server == null ? null : (id: server.id, name: server.name);
    }

    return ServerReachCubit(
      unreachable: servers.realtime.unreachable,
      selected: servers.stream.map(selectedOf).distinct(),
      initial: selectedOf(servers.state),
    );
  }

  void _onUnreachable() {
    final down = _unreachable.value;
    _downSince.removeWhere((id, _) => !down.contains(id));
    final now = DateTime.now();
    for (final id in down) {
      _downSince.putIfAbsent(id, () => now);
    }
    _evaluate();
  }

  void _evaluate() {
    _timer?.cancel();
    _timer = null;
    if (isClosed) return;
    final selected = _selected;
    final since = selected == null ? null : _downSince[selected.id];
    if (selected == null || since == null) return _show(null);
    final left = _settle - DateTime.now().difference(since);
    if (left <= Duration.zero) return _show(selected.name);
    _show(null);
    _timer = Timer(left, _evaluate);
  }

  void _show(String? name) {
    if (state.unreachableName != name) {
      emit(ServerReachState(unreachableName: name));
    }
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _unreachable.removeListener(_onUnreachable);
    await _selectedSub?.cancel();
    return super.close();
  }
}
