import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/apis/dm_calls_api.dart';
import '../../../data/classes/dm_call.dart';
import '../../../data/classes/dm_call_place.dart';
import '../../../data/classes/notice.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/app_sound.dart';
import '../../../data/enums/dm_call_outcome.dart';
import '../../../data/enums/notification_level.dart';
import '../../../data/participant_identity.dart';
import '../../../data/repositories/session_repository.dart';
import '../../helper_methods.dart';
import '../../services/before_quit.dart';
import '../../services/call_refusal.dart';
import '../../services/dm_call_ledger.dart';
import '../../services/host_platform.dart';
import '../../services/notification_service.dart';
import '../../services/server_realtime.dart';
import '../../services/server_topics.dart';
import '../../services/sound_service.dart';
import '../../services/voice_keys.dart';
import '../../services/window_focus_service.dart';
import '../app/app_cubit.dart';
import '../livekit/livekit_cubit.dart';
import '../notifications/server_notifications_cubit.dart';
import '../server/server_cubit.dart';
import '../vault/vault_cubit.dart';

part 'dm_call_actions.dart';
part 'dm_call_state.dart';
part 'dm_call_watch.dart';

/// Calls between two members (`dm_calls`), on every server this device is
/// on.
///
/// The row is the call. This cubit follows it — on each server's own topic,
/// where the database says a call rang, was answered or ended — and does what
/// following it asks: rings, stops ringing, joins the room when the call is
/// ours to be in, leaves it when the call is over. The room itself is
/// [LiveKitCubit]'s, joined through `connectToDmCall`; how a call *sounds* is
/// no different from a channel's.
///
/// Every server, not only the selected one, because a call is the one thing
/// that cannot wait for somebody to go and look: `ServerNotificationsCubit`
/// holds every server's topic for the unread badge, and this rides the same
/// shared connections.
class DmCallCubit extends Cubit<DmCallState>
    with _DmCallActionsMixin, _DmCallWatchMixin {
  @override
  final ServerCubit _serverCubit;
  final SessionRepository _session;
  @override
  final DmCallsApi _calls;
  @override
  final LiveKitCubit _livekit;
  @override
  final VaultCubit _vault;
  @override
  final AppCubit _app;
  @override
  final CryptoRepository _crypto;

  /// Where a conversation's level is read, to keep a muted person's call
  /// quiet. Injected after construction: it is built later, and a call rings
  /// perfectly well without it — just never quietly.
  @override
  ServerNotificationsCubit? _notifications;

  void injectNotifications(ServerNotificationsCubit cubit) =>
      _notifications = cubit;

  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<LiveKitState>? _livekitSub;

  /// One lease on each server's own topic for the current user, and the token
  /// it was opened under — a new token is a moment to ask again, because a
  /// doorbell can have gone by while the old one was being refused.
  final Map<String, ({RealtimeLease lease, String token})> _topics = {};

  /// A burst of changes — ring, answer and a second device answering too —
  /// is one question per server.
  final Map<String, Timer> _debounce = {};

  DmCallCubit({
    required ServerCubit serverCubit,
    required SessionRepository session,
    required LiveKitCubit livekitCubit,
    required VaultCubit vaultCubit,
    required AppCubit appCubit,
    CryptoRepository? crypto,
  }) : _serverCubit = serverCubit,
       _session = session,
       _calls = DmCallsApi(session: session),
       _livekit = livekitCubit,
       _vault = vaultCubit,
       _app = appCubit,
       _crypto = crypto ?? CryptoRepository(),
       super(const DmCallState()) {
    _serverSub = serverCubit.stream.listen((_) => _sync());
    _livekitSub = livekitCubit.stream.listen(_onLiveKit);
    scheduleMicrotask(_sync);
    BeforeQuit.instance.add(hangUp);
  }

  @override
  Server? _server(String serverId) =>
      _serverCubit.state.servers.where((s) => s.id == serverId).firstOrNull;

  // ──────────────────────────────────────────────────────────
  // Listening on every server
  // ──────────────────────────────────────────────────────────

  void _sync() {
    if (isClosed) return;
    final wanted = <String>{};
    for (final server in _serverCubit.state.servers) {
      final user = server.user;
      if (user == null ||
          server.supabaseKey == null ||
          server.token.isEmpty ||
          user.isBanned) {
        continue;
      }
      wanted.add(server.id);
      final held = _topics[server.id];
      if (held == null) {
        // Not under a token that is about to be refused — the notifications
        // cubit refreshes it, and this runs again when it lands.
        if (server.isTokenNearExpiry) continue;
        final lease = _session.realtime.join(
          server,
          ServerTopics.user(user.id),
        );
        if (lease == null) continue;
        lease.onBroadcast(ServerEvent.dmCalls, (_) => _ask(server.id));
        _topics[server.id] = (lease: lease, token: server.token);
        _ask(server.id);
      } else if (held.token != server.token) {
        _topics[server.id] = (lease: held.lease, token: server.token);
        _ask(server.id);
      }
    }
    for (final id in _topics.keys.toList()) {
      if (wanted.contains(id)) continue;
      unawaited(_topics.remove(id)?.lease.release());
      _forgetServer(id);
    }
  }

  /// A server left, or banned us: nothing on it can ring here any more.
  void _forgetServer(String serverId) {
    final active = state.active;
    if (active?.serverId == serverId) unawaited(_dropActive(hangUpRoom: true));
    emit(
      state.copyWith(
        incoming: [
          for (final entry in state.incoming)
            if (entry.serverId != serverId) entry,
        ],
      ),
    );
    _syncSounds();
  }

  @override
  void _ask(String serverId) {
    _debounce[serverId]?.cancel();
    _debounce[serverId] = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(refresh(serverId)),
    );
  }

  /// Ask [serverId] which calls are going, and fold the answer in.
  Future<void> refresh(String serverId) async {
    final server = _server(serverId);
    final myId = server?.user?.id;
    if (server == null || myId == null || isClosed) return;

    final activeId = state.active?.serverId == serverId
        ? state.active!.call.id
        : null;
    final known = <String>[
      ?activeId,
      for (final entry in state.incoming)
        if (entry.serverId == serverId) entry.call.id,
    ];
    final response = await _calls.myDmCalls(server, known: known);
    if (!response.success || isClosed) return;

    final before = state.incoming;
    final folded = DmCallLedger.apply(
      serverId: serverId,
      myId: myId,
      ringing: [for (final e in before) (serverId: e.serverId, call: e.call)],
      // Read again: the call we are in may have changed while this was out.
      activeId: state.active?.serverId == serverId
          ? state.active!.call.id
          : null,
      fetched: DmCall.listFrom(response.data),
      now: DateTime.now(),
    );

    final names = {for (final s in _serverCubit.state.servers) s.id: s.name};
    final incoming = [
      for (final entry in folded.ringing)
        IncomingDmCall(
          serverId: entry.serverId,
          serverName: names[entry.serverId] ?? 'Rift',
          call: entry.call,
        ),
    ];
    final fresh = [
      for (final entry in incoming)
        if (!before.any((b) => b.call.id == entry.call.id)) entry,
    ];
    emit(state.copyWith(incoming: incoming));

    for (final entry in fresh) {
      _announceRing(entry);
    }
    for (final call in folded.missed) {
      _announceMissed(call, names[serverId]);
    }
    // A ring that stopped any other way — answered on another device, or
    // given up on at once — leaves nothing in the shade. A missed one is the
    // push's to turn into "Missed call".
    for (final gone in before) {
      if (gone.serverId != serverId) continue;
      if (incoming.any((e) => e.call.id == gone.call.id)) continue;
      if (folded.missed.any((m) => m.id == gone.call.id)) continue;
      unawaited(NotificationService.instance.cancelCall(gone.call.id));
    }
    final active = folded.active;
    if (active != null) await _onActiveRow(active);
    _syncSounds();
    _syncTimers();
  }

  @override
  Future<void> close() async {
    BeforeQuit.instance.remove(hangUp);
    await _serverSub?.cancel();
    await _livekitSub?.cancel();
    for (final timer in _debounce.values) {
      timer.cancel();
    }
    for (final held in _topics.values) {
      unawaited(held.lease.release());
    }
    _topics.clear();
    _stopTimers();
    unawaited(SoundService.instance.stopLoop());
    return super.close();
  }
}
