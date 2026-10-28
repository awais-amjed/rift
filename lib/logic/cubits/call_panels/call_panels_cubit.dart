import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/apis/channel_messages_api.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/channel_type.dart';
import '../../../data/repositories/session_repository.dart';
import '../../helper_methods.dart';
import '../../services/broadcast_payload.dart';
import '../../services/live_items.dart';
import '../../services/plain_rows.dart';
import '../../services/server_realtime.dart';
import '../../services/server_topics.dart';

part 'call_panels_state.dart';

/// The players of the bots in this device's call on one server, from whichever
/// channel each was posted in, for the bar above every channel's message box:
/// the people in a call hear its music in every channel they read, so the
/// player follows them there (BOTS.md §6).
///
/// Idle until there is a call here. Then every text channel the caller can
/// read is asked once what is live in it (`channel_live_messages`), and the
/// doorbells keep that current: a bot in the call posting a message has its
/// channel asked again, and a change to a held panel re-reads that panel.
/// Who is in the call only filters what is held, so somebody joining asks
/// nothing.
class CallPanelsCubit extends Cubit<CallPanelsState> {
  final SessionRepository _session;
  final CryptoRepository _crypto;
  final String _serverId;

  CallPanelsCubit({
    required SessionRepository session,
    required String serverId,
    CryptoRepository? crypto,
  }) : _session = session,
       _serverId = serverId,
       _crypto = crypto ?? CryptoRepository(),
       super(const CallPanelsState());

  StreamSubscription<Set<String>>? _callSub;
  StreamSubscription<void>? _serverSub;

  /// Who is in this device's call here; empty when there is none.
  Set<String> _callIds = const {};

  /// Every live panel each channel answered, whoever's, newest first.
  final Map<String, List<ChatMessage>> _byChannel = {};

  /// The server's topic and each private channel's, by topic name.
  final Map<String, RealtimeLease> _feeds = {};

  /// Bumped when the call ends, so an answer to a read from before is dropped.
  int _generation = 0;

  ChannelMessagesApi get _api => ChannelMessagesApi(_session.on(_serverId));

  /// Follow [callUserIds], the people in this device's call on this server,
  /// starting from [initial].
  void watchCall(Stream<Set<String>> callUserIds, {Set<String>? initial}) {
    if (initial != null) _onCall(initial);
    _callSub = callUserIds.listen(_onCall);
  }

  void _onCall(Set<String> ids) {
    if (isClosed || setEquals(ids, _callIds)) return;
    final started = _callIds.isEmpty;
    _callIds = ids;
    if (ids.isEmpty) return _stop();
    if (started) {
      _serverSub = _session.changes.listen((_) => _syncFeeds());
      _syncFeeds();
      unawaited(_readAll());
    } else {
      _publish();
    }
  }

  void _stop() {
    _generation++;
    _byChannel.clear();
    unawaited(_serverSub?.cancel());
    _serverSub = null;
    _releaseFeeds();
    emit(const CallPanelsState());
  }

  /// The text channels the caller can read: the server lists no others.
  List<String> _textChannels(Server server) => [
    for (final channel in server.channels)
      if (channel.channelType == ChannelType.text) channel.id,
  ];

  Future<void> _readAll() async {
    final server = _session.serverById(_serverId);
    if (server == null) return;
    await Future.wait(_textChannels(server).map(_readChannel));
  }

  /// Ask [channelId] what is live in it, and keep its panels.
  Future<void> _readChannel(String channelId) async {
    final generation = _generation;
    final response = await _api.listLiveMessages(channelId: channelId);
    if (isClosed || generation != _generation) return;
    if (!response.success) {
      HelperMethods.printDebug('[Call panels] read failed: ${response.error}');
      return;
    }
    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .cast<Map<String, dynamic>>();
    final opened = <ChatMessage>[];
    for (final row in rows) {
      final message = await _open(row, channelId);
      if (message != null) opened.add(message);
    }
    if (isClosed || generation != _generation) return;
    _byChannel[channelId] = opened;
    _publish();
  }

  /// Re-read one held panel after its change doorbell.
  Future<void> _rereadPanel(String channelId, String messageId) async {
    final id = int.tryParse(messageId);
    if (id == null) return;
    final generation = _generation;
    final response = await _api.getChatMessage(
      channelId: channelId,
      messageId: id,
    );
    if (isClosed || generation != _generation || !response.success) return;
    final row = (response.data as Map<String, dynamic>)['message'];
    final message = row is Map<String, dynamic>
        ? await _open(row, channelId)
        : null;
    if (isClosed || generation != _generation) return;
    final held = _byChannel[channelId];
    if (held == null) return;
    // Its new copy, or gone: a panel redrawn without the mark has ended.
    _byChannel[channelId] = [
      for (final m in held)
        if (m.id != messageId) m else ?message,
    ];
    _publish();
  }

  /// A live panel from [row], or null for anything else. Panels are never
  /// sealed — the bot holds no channel key — so a sealed row is a poll.
  Future<ChatMessage?> _open(Map<String, dynamic> row, String channelId) async {
    if (row['key_version'] != 0) return null;
    try {
      final message = await PlainRows.open(
        _crypto,
        row,
        channelId: channelId,
        localUserId: _session.serverById(_serverId)?.user?.id,
        plainChannel: false,
      );
      return (message?.panel?.live ?? false) ? message : null;
    } catch (e) {
      HelperMethods.printDebug('[Call panels] dropped row ${row['id']}: $e');
      return null;
    }
  }

  void _publish() {
    if (isClosed) return;
    final channelOf = <String, String>{};
    final all = <ChatMessage>[];
    for (final MapEntry(key: channelId, value: rows) in _byChannel.entries) {
      for (final message in LiveItems.callPanels(rows, callUserIds: _callIds)) {
        channelOf[message.id] = channelId;
        all.add(message);
      }
    }
    all.sort(
      (a, b) => (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0),
    );
    emit(CallPanelsState(panels: all, channelOf: channelOf));
  }

  // ── Doorbells ─────────────────────────────────────────────

  /// Hold the server's topic, where an open channel's doorbells ring, and
  /// each private channel's own. Reconciled when the server's list moves.
  void _syncFeeds() {
    final server = _session.serverById(_serverId);
    if (isClosed || server == null || _callIds.isEmpty) return;
    final wanted = {
      ServerTopics.server(server.id),
      for (final channel in server.channels)
        if (channel.isPrivate && channel.channelType == ChannelType.text)
          ServerTopics.channel(channel.id),
    };
    for (final topic in _feeds.keys.toList()) {
      if (!wanted.contains(topic)) unawaited(_feeds.remove(topic)?.release());
    }
    for (final topic in wanted) {
      if (_feeds.containsKey(topic)) continue;
      final feed = _session.realtime.join(server, topic);
      if (feed == null) continue;
      feed
        ..onReopen(() => unawaited(_readAll()))
        ..onBroadcast(ServerEvent.message, _onMessage)
        ..onBroadcast(ServerEvent.messageChanged, _onMessageChanged);
      _feeds[topic] = feed;
    }
  }

  /// A bot in the call posted: its channel may have a new player.
  void _onMessage(Map<String, dynamic> message) {
    final channelId = BroadcastPayload.stringOf(message, 'channel_id');
    final sender = BroadcastPayload.stringOf(message, 'sender_id');
    if (channelId == null || !_callIds.contains(sender)) return;
    unawaited(_readChannel(channelId));
  }

  void _onMessageChanged(Map<String, dynamic> message) {
    final channelId = BroadcastPayload.stringOf(message, 'channel_id');
    final messageId = BroadcastPayload.stringOf(message, 'message_id');
    if (channelId == null || messageId == null) return;
    final held = _byChannel[channelId]?.any((m) => m.id == messageId) ?? false;
    if (held) unawaited(_rereadPanel(channelId, messageId));
  }

  void _releaseFeeds() {
    for (final feed in _feeds.values) {
      unawaited(feed.release());
    }
    _feeds.clear();
  }

  @override
  Future<void> close() async {
    await _callSub?.cancel();
    await _serverSub?.cancel();
    _releaseFeeds();
    return super.close();
  }
}
