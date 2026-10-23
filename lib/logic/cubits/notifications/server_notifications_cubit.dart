import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/apis/members_api.dart';
import '../../../data/apis/unread_api.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/app_sound.dart';
import '../../../data/enums/home_surface.dart';
import '../../../data/enums/notification_level.dart';
import '../../../data/repositories/session_repository.dart';
import '../../services/broadcast_payload.dart';
import '../../services/notification_ids.dart';
import '../../services/notification_service.dart';
import '../../services/per_server_map.dart';
import '../../services/server_realtime.dart';
import '../../services/server_topics.dart';
import '../../services/sound_service.dart';
import '../../services/window_focus_service.dart';
import '../app/app_cubit.dart';
import '../channel_chat/channel_chat_cubit.dart';
import '../dm/dm_cubit.dart';

part 'server_notifications_delivery.dart';
part 'server_notifications_levels.dart';
part 'server_notifications_names.dart';
part 'server_notifications_read.dart';
part 'server_notifications_state.dart';
part 'server_notifications_subscriptions.dart';

/// Unread badges and OS notifications for **every joined server** at once —
/// not just the one you're looking at — so a channel you never opened, on a
/// server you aren't viewing, still badges.
///
/// Responsibilities:
/// - **Per-(server, channel) unread** and **per-(server, peer) DM unread** —
///   each server is seeded by `unread_counts()` ([UnreadApi]) and kept live by
///   the ids the database broadcasts to that server's topics.
/// - **OS notifications** for channel messages while the window is unfocused
///   (any server). DM notifications come from [DmCubit] instead, which can
///   decrypt the body for a preview.
/// - **Read tracking** — opening a channel or a conversation, a message landing
///   in the open+focused one, or refocusing the window moves its read cursor
///   (`mark_read`), clearing the badge.
/// - **Token freshness** — background servers' JWTs are refreshed before they
///   expire (via [SessionRepository.reAuthenticate]) so their subscriptions
///   don't lapse while another server is in focus.
class ServerNotificationsCubit extends Cubit<NotificationsState>
    with
        _PeerNamesMixin,
        _SubscriptionsMixin,
        _ReadMarkingMixin,
        _LevelsMixin,
        _DeliveryMixin {
  @override
  final SessionRepository _session;
  final AppCubit _appCubit;
  final ChannelChatCubit _chatCubit;
  @override
  final DmCubit _dmCubit;
  StreamSubscription<void>? _serverSub;
  StreamSubscription<ChannelChatState>? _chatSub;
  StreamSubscription<DmState>? _dmSub;
  StreamSubscription<AppState>? _appSub;
  Timer? _refreshTimer;

  @override
  final Map<String, _ServerSub> _subs = {};

  /// The open text channel and the server it belongs to. Messages arriving here while it's on screen and focused are read,
  /// not badged.
  @override
  String? _openServerId;
  @override
  String? _openChannelId;

  /// The open DM conversation's peer, and the server it belongs to. Separate
  /// from the channel pair above because both can be open at once — a channel
  /// stays loaded behind the DM surface.
  @override
  String? _openDmServerId;
  @override
  String? _openPeerId;

  /// The last surface seen, so an [AppState] change that isn't a navigation
  /// doesn't re-run the read sweep.
  HomeSurface _lastSurface;

  ServerNotificationsCubit({
    required SessionRepository session,
    required ChannelChatCubit chatCubit,
    required DmCubit dmCubit,
    required AppCubit appCubit,
  }) : _session = session,
       _chatCubit = chatCubit,
       _dmCubit = dmCubit,
       _appCubit = appCubit,
       _lastSurface = appCubit.state.surface,
       super(const NotificationsState()) {
    _serverSub = session.changes.listen((_) => _sync());
    _chatSub = chatCubit.stream.listen(_onChatChanged);
    // The open channel's notification is raised over there, because only that
    // side holds the key and can tell a mention from an ordinary line. The
    // *level* is here, with every other server's. Handing it over as a lookup
    // rather than duplicating the fetch is what keeps one answer to "may this
    // channel interrupt" instead of two that drift.
    chatCubit.setNotificationLevelSource(
      (channelId) =>
          state.channelLevel(chatCubit.openServerId ?? '', channelId),
    );
    _dmSub = dmCubit.stream.listen(_onDmChanged);
    _appSub = appCubit.stream.listen(_onAppStateChanged);
    WindowFocusService.instance.focused.addListener(_onFocusChanged);
    if (chatCubit.state.channelId != null) {
      _openServerId = chatCubit.openServerId;
      _openChannelId = chatCubit.state.channelId;
    }
    if (dmCubit.state.openPeerId != null) {
      _openDmServerId = dmCubit.serverId;
      _openPeerId = dmCubit.state.openPeerId;
    }
    // Keep background servers' JWTs fresh so their subscriptions don't lapse.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _sync());
    _sync();
  }

  /// Ask a server what is unread and fold the answer into state.
  ///
  /// One RPC per server — `unread_counts()` counts messages above each read
  /// cursor and returns `{channels, dms, prefs}` — where this used to fetch
  /// every unread notification row and tally them here. The levels ride along
  /// with the counts because drawing a badge and deciding whether it may
  /// interrupt are the same question asked twice, and asking them a round trip
  /// apart is how a muted channel gets one notification anyway. Whatever the
  /// user is looking at is then marked read, which is what stops a badge
  /// appearing for the channel already on screen.
  @override
  Future<void> _seed(String serverId) async {
    if (!_subs.containsKey(serverId)) return;
    // Best-effort — a failed seed just means no badges until the next event.
    final response = await UnreadApi(_session.on(serverId)).unreadCounts();
    if (isClosed || !_subs.containsKey(serverId)) return;
    final data = response.data;
    if (!response.success || data is! Map) return;

    final prefs = data['prefs'];
    final servers = NotificationLevel.mapFrom(
      prefs is Map ? prefs['servers'] : null,
      // No fallback to drop against: an absent server row is "no opinion",
      // and the level that would mean that is never stored, so anything
      // here is a real answer somebody gave.
      fallback: null,
    );
    emit(
      state.withServerCounts(
        serverId,
        serverPref: servers[serverId],
        channels: _countsOf(data['channels']),
        dms: _countsOf(data['dms']),
        // Kept whole, defaults included: inside a server a stored level
        // that matches the default still outranks the server's own
        // (`NotificationLevel.resolve`), and dropping it here let a channel
        // set to "Only @mentions" follow the server up to "All".
        channelPrefs: NotificationLevel.mapFrom(
          prefs is Map ? prefs['channels'] : null,
          fallback: null,
        ),
        dmPrefs: NotificationLevel.mapFrom(
          prefs is Map ? prefs['dms'] : null,
          fallback: null,
        ),
      ),
    );
    _markOnScreenRead(onlyServerId: serverId);
  }

  /// `{id: n}` out of the RPC's json, ignoring anything malformed rather than
  /// letting one bad entry cost every badge on the server.
  static Map<String, int> _countsOf(dynamic raw) {
    if (raw is! Map) return const {};
    final counts = <String, int>{};
    raw.forEach((key, value) {
      final n = value is int ? value : int.tryParse('$value');
      if (key is String && n != null && n > 0) counts[key] = n;
    });
    return counts;
  }

  // ── Read tracking ─────────────────────────────────────────────

  /// A cubit can't ask whether a widget is on screen, so "is the user actually
  /// looking at this" comes from the surface: channels only render on
  /// [HomeSurface.server], server DMs only on [HomeSurface.serverDms].
  ///
  /// Without this the open ids would outlive their view. Opening a conversation
  /// and then going back to the channels leaves `_openPeerId` set — every DM
  /// that arrived would be marked read on the spot and the badge would never
  /// appear, which is the bug the count-of-conversations badge was hiding.
  @override
  bool get _channelOnScreen => _appCubit.state.surface == HomeSurface.server;

  @override
  bool get _dmOnScreen => _appCubit.state.surface == HomeSurface.serverDms;

  void _onAppStateChanged(AppState appState) {
    if (appState.surface == _lastSurface) return;
    _lastSurface = appState.surface;
    // Navigating *to* a surface reads what was waiting on it.
    _markOnScreenRead();
  }

  /// A channel opened. Not always by hand: switching server re-opens that
  /// server's last channel, which is why this defers to the surface too —
  /// otherwise hopping between servers while reading DMs would quietly clear
  /// every channel badge on the way past. When the open *is* a navigation, the
  /// surface change lands in the same turn and [_onAppStateChanged] finishes
  /// the job.
  void _onChatChanged(ChannelChatState chatState) {
    final channelId = chatState.channelId;
    if (channelId == _openChannelId) return;
    _openChannelId = channelId;
    if (channelId == null) {
      _openServerId = null;
      return;
    }
    final serverId = _chatCubit.openServerId;
    _openServerId = serverId;
    if (serverId != null && _channelOnScreen) {
      markChannelRead(serverId, channelId);
    }
  }

  void _onDmChanged(DmState dmState) {
    final peerId = dmState.openPeerId;
    if (peerId == _openPeerId) return;
    _openPeerId = peerId;
    if (peerId == null) {
      _openDmServerId = null;
      return;
    }
    final serverId = _dmCubit.serverId;
    _openDmServerId = serverId;
    if (serverId != null && _dmOnScreen) markDmRead(serverId, peerId);
  }

  void _onFocusChanged() {
    if (WindowFocusService.instance.isFocused) _markOnScreenRead();
  }

  /// Marks whatever the user is currently looking at read. [onlyServerId]
  /// narrows it to one server, for a re-seed that only refreshed that one.
  void _markOnScreenRead({String? onlyServerId}) {
    final channelServerId = _openServerId;
    if (_channelOnScreen &&
        channelServerId != null &&
        _openChannelId != null &&
        (onlyServerId == null || onlyServerId == channelServerId)) {
      markChannelRead(channelServerId, _openChannelId!);
    }
    final dmServerId = _openDmServerId;
    if (_dmOnScreen &&
        dmServerId != null &&
        _openPeerId != null &&
        (onlyServerId == null || onlyServerId == dmServerId)) {
      markDmRead(dmServerId, _openPeerId!);
    }
  }

  // ── Teardown ──────────────────────────────────────────────────

  @override
  Server? _serverById(String serverId) {
    for (final s in _session.servers) {
      if (s.id == serverId) return s;
    }
    return null;
  }

  @override
  Future<void> close() async {
    WindowFocusService.instance.focused.removeListener(_onFocusChanged);
    _refreshTimer?.cancel();
    await _serverSub?.cancel();
    await _chatSub?.cancel();
    await _dmSub?.cancel();
    await _appSub?.cancel();
    for (final id in _subs.keys.toList()) {
      _teardownServer(id);
    }
    return super.close();
  }
}
