import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/server.dart';
import '../../../data/enums/home_surface.dart';
import '../../services/notification_service.dart';
import '../../services/window_focus_service.dart';
import '../app/app_cubit.dart';
import '../channel_chat/channel_chat_cubit.dart';
import '../dm/dm_cubit.dart';
import '../server/server_cubit.dart';

part 'server_notifications_state.dart';
part 'server_notifications_subscriptions.dart';
part 'server_notifications_read.dart';

/// One authenticated Realtime + REST connection **per joined server** to its
/// `notifications` table (RLS-scoped to `auth.uid()`), so unread badges and OS
/// notifications work everywhere at once — not just on the server you're looking
/// at. Rows are fanned out by `send_message` and `send_dm`, so this covers
/// channels the user never opened, on servers they aren't currently viewing.
///
/// Responsibilities:
/// - **Per-(server, channel) unread** and **per-(server, peer) DM unread** —
///   each subscription is seeded by an authenticated REST fetch and kept live by
///   Postgres-Changes INSERTs.
/// - **OS notifications** for channel messages while the window is unfocused
///   (any server). DM notifications come from [DmCubit] instead, which can
///   decrypt the body for a preview.
/// - **Read tracking** — opening a channel or a conversation, a message landing
///   in the open+focused one, or refocusing the window marks it read
///   (`read_at`), clearing the badge and letting the retention job (migration
///   008) prune the rows.
/// - **Token freshness** — background servers' JWTs are refreshed before they
///   expire (via [ServerCubit.reAuthenticateServer]) so their subscriptions
///   don't lapse while another server is in focus.
class ServerNotificationsCubit extends Cubit<NotificationsState>
    with _SubscriptionsMixin, _ReadMarkingMixin {
  @override
  final ServerCubit _serverCubit;
  final AppCubit _appCubit;
  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<ChannelChatState>? _chatSub;
  StreamSubscription<DmState>? _dmSub;
  StreamSubscription<AppState>? _appSub;
  Timer? _refreshTimer;

  @override
  final Map<String, _ServerSub> _subs = {};

  /// The open text channel and the server it belongs to (always the selected
  /// server). Messages arriving here while it's on screen and focused are read,
  /// not badged.
  String? _openServerId;
  String? _openChannelId;

  /// The open DM conversation's peer, and the server it belongs to. Separate
  /// from the channel pair above because both can be open at once — a channel
  /// stays loaded behind the DM surface.
  String? _openDmServerId;
  String? _openPeerId;

  /// The last surface seen, so an [AppState] change that isn't a navigation
  /// doesn't re-run the read sweep.
  HomeSurface _lastSurface;

  ServerNotificationsCubit({
    required ServerCubit serverCubit,
    required ChannelChatCubit chatCubit,
    required DmCubit dmCubit,
    required AppCubit appCubit,
  }) : _serverCubit = serverCubit,
       _appCubit = appCubit,
       _lastSurface = appCubit.state.surface,
       super(const NotificationsState()) {
    _serverSub = serverCubit.stream.listen((_) => _sync());
    _chatSub = chatCubit.stream.listen(_onChatChanged);
    _dmSub = dmCubit.stream.listen(_onDmChanged);
    _appSub = appCubit.stream.listen(_onAppStateChanged);
    WindowFocusService.instance.focused.addListener(_onFocusChanged);
    if (chatCubit.state.channelId != null) {
      _openServerId = serverCubit.state.selectedServerId;
      _openChannelId = chatCubit.state.channelId;
    }
    if (dmCubit.state.openPeerId != null) {
      _openDmServerId = serverCubit.state.selectedServerId;
      _openPeerId = dmCubit.state.openPeerId;
    }
    // Keep background servers' JWTs fresh so their subscriptions don't lapse.
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _sync());
    _sync();
  }

  /// Ask a server what is unread and fold the answer into state.
  ///
  /// One RPC per server — `unread_counts()` counts messages above each read
  /// cursor and returns `{channels: {...}, dms: {...}}` — where this used to
  /// fetch every unread notification row and tally them here. Whatever the user
  /// is looking at is then marked read, which is what stops a badge appearing
  /// for the channel already on screen.
  @override
  Future<void> _seed(String serverId) async {
    final sub = _subs[serverId];
    if (sub == null) return;
    try {
      final data = await sub.client.rpc('unread_counts');
      if (isClosed || !_subs.containsKey(serverId)) return;
      if (data is! Map) return;

      emit(
        state.withServerCounts(
          serverId,
          channels: _countsOf(data['channels']),
          dms: _countsOf(data['dms']),
        ),
      );
      _markOnScreenRead(onlyServerId: serverId);
    } catch (_) {
      // Best-effort — a failed seed just means no badges until the next event.
    }
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

  // ── Live delivery ─────────────────────────────────────────────

  /// A message landed in a channel on this server. Realtime only delivers rows
  /// this member could have selected, so arriving here already means "you can
  /// see this".
  @override
  void _onChannelMessage(String serverId, Map<String, dynamic> row) {
    if (isClosed) return;
    final channelId = row['channel_id'] as String?;
    if (channelId == null) return;
    // Our own messages come back over the same subscription.
    if (row['sender_id'] == _subs[serverId]?.userId) return;

    final focused = WindowFocusService.instance.isFocused;

    // Looking at this exact channel → it's read; don't badge or notify.
    if (focused &&
        _channelOnScreen &&
        serverId == _openServerId &&
        channelId == _openChannelId) {
      markChannelRead(serverId, channelId);
      return;
    }

    emit(state.incremented(serverId, channelId));

    if (!focused) {
      final server = _serverById(serverId);
      String? channelName;
      for (final c in server?.channels ?? const []) {
        if (c.id == channelId) {
          channelName = c.name;
          break;
        }
      }
      NotificationService.instance.showMessage(
        title: server?.name ?? 'Rift',
        body: channelName != null
            ? 'New message in #$channelName'
            : 'New message',
      );
    }
  }

  /// Badge an incoming DM. No OS notification here: [DmCubit] raises those off
  /// the conversation list, where it can decrypt a preview and name the sender
  /// — this row is ciphertext without the key. (It only does so for the
  /// selected server, so a DM on a background server badges without notifying.)
  @override
  void _onDmMessage(String serverId, Map<String, dynamic> row) {
    if (isClosed) return;
    final peerId = row['sender_id'] as String?;
    if (peerId == null) return;

    if (WindowFocusService.instance.isFocused &&
        _dmOnScreen &&
        serverId == _openDmServerId &&
        peerId == _openPeerId) {
      markDmRead(serverId, peerId);
      return;
    }
    emit(state.incrementedDm(serverId, peerId));
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
  bool get _channelOnScreen => _appCubit.state.surface == HomeSurface.server;

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
    final serverId = _serverCubit.state.selectedServerId;
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
    final serverId = _serverCubit.state.selectedServerId;
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

  Server? _serverById(String serverId) {
    for (final s in _serverCubit.state.servers) {
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
