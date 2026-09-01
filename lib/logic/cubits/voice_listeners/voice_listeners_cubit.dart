import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../server/server_cubit.dart';

/// Which bots can hear which voice channels, for the marker in the sidebar.
///
/// Its own cubit rather than a field on [ChannelPresenceCubit], which is next
/// door and answers a question that sounds similar. That one is about *live*
/// state and is built entirely around two realtime transports and their
/// budgets; this is a row in a table that changes when an admin clicks
/// something. Putting a query in there would have meant explaining, in a class
/// whose every comment is about publish windows, why one thing in it is not.
///
/// The marker this feeds is BOTS.md §6's fourth rule arriving in voice: the
/// admin grants, and everybody who ever speaks in that room pays for it. A
/// notice that lived in the dialog where the decision was made would reach
/// exactly the wrong people, so the channel says it, standing, to everyone.
class VoiceListenersCubit extends Cubit<Map<String, List<String>>> {
  final ServerCubit _serverCubit;
  StreamSubscription<ServerState>? _serverSub;
  String? _serverId;

  VoiceListenersCubit({required ServerCubit serverCubit})
    : _serverCubit = serverCubit,
      super(const {}) {
    _serverSub = serverCubit.stream.listen(_onServerChanged);
    _onServerChanged(serverCubit.state);
  }

  /// The bots that can hear [channelId], by name. Empty is the common case and
  /// the one that draws nothing.
  List<String> listening(String channelId) => state[channelId] ?? const [];

  void _onServerChanged(ServerState serverState) {
    final id = serverState.selectedServer?.id;
    if (id == _serverId) return;
    _serverId = id;
    // Clear first. Carrying the previous server's grants across a switch would
    // put a recording light on a channel that never had one, which is the one
    // direction this marker must never be wrong in.
    emit(const {});
    if (id != null) unawaited(refresh());
  }

  /// Re-read the grants. Called on server change and after one is changed.
  Future<void> refresh() async {
    final byChannel = await _serverCubit.voiceListenersByChannel();
    if (isClosed) return;
    emit(byChannel);
  }

  @override
  Future<void> close() {
    _serverSub?.cancel();
    return super.close();
  }
}
