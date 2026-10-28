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

/// This device's call on one server: its voice channel (null for a DM call)
/// and who is in it. Empty [userIds] means no call here.
typedef CallSeen = ({String? channelId, Set<String> userIds});

/// The players of the bots in this device's call on one server, from whichever
/// channel each was posted in, for the bar above every channel's message box:
/// the people in a call hear its music in every channel they read, so the
/// player follows them there (BOTS.md §6).
///
/// Idle until there is a call here. Then the call is asked for its players
/// (`call_live_messages`), which a bot that names its call reaches from any
/// channel, one the caller cannot read included: the player is the call's.
/// Every text channel the caller can read is asked as well
/// (`channel_live_messages`), for a bot or a server from before players named
/// their call. The doorbells keep both current: a bot in the call posting a
/// message has its channel and the call asked again, and a change to a held
/// panel re-reads that panel. Who is in the call only filters what is held,
/// so somebody joining asks nothing.
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

  StreamSubscription<CallSeen>? _callSub;
  StreamSubscription<void>? _serverSub;

  /// Who is in this device's call here; empty when there is none.
  Set<String> _callIds = const {};

  /// The call's voice channel, null in a DM call or none.
  String? _callChannel;

  /// Every live panel each channel answered, whoever's, newest first.
  final Map<String, List<ChatMessage>> _byChannel = {};

  /// What the call answered, newest first, and the channel each was posted in.
  List<ChatMessage> _fromCall = const [];
  Map<String, String> _fromCallChannel = const {};

  /// The server's topic and each private channel's, by topic name.
  final Map<String, RealtimeLease> _feeds = {};

  /// Bumped when the call ends, so an answer to a read from before is dropped.
  int _generation = 0;

  ChannelMessagesApi get _api => ChannelMessagesApi(_session.on(_serverId));

  /// Follow [calls], this device's call on this server, starting from
  /// [initial].
  void watchCall(Stream<CallSeen> calls, {CallSeen? initial}) {
    if (initial != null) _onCall(initial);
    _callSub = calls.listen(_onCall);
  }

  void _onCall(CallSeen call) {
    final ids = call.userIds;
    final moved = ids.isNotEmpty && call.channelId != _callChannel;
    if (isClosed || (!moved && setEquals(ids, _callIds))) return;
    final started = _callIds.isEmpty;
    _callIds = ids;
    if (ids.isEmpty) return _stop();
    _callChannel = call.channelId;
    if (started) {
      _serverSub = _session.changes.listen((_) => _syncFeeds());
      _syncFeeds();
      unawaited(_readAll());
    } else if (moved) {
      // Another call on this server: its players, not the last one's.
      _fromCall = const [];
      _fromCallChannel = const {};
      _syncFeeds();
      unawaited(_readCall());
      _publish();
    } else {
      _publish();
    }
  }

  void _stop() {
    _generation++;
    _callChannel = null;
    _byChannel.clear();
    _fromCall = const [];
    _fromCallChannel = const {};
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
    await Future.wait([
      _readCall(),
      ..._textChannels(server).map(_readChannel),
    ]);
  }

  /// Ask the call for its players, wherever each was posted. A server from
  /// before the read refuses it, and the channels' answers are all there is.
  Future<void> _readCall() async {
    final callId = _callChannel;
    if (callId == null) return;
    final generation = _generation;
    final response = await _api.listCallLiveMessages(callId: callId);
    if (isClosed || generation != _generation || callId != _callChannel) {
      return;
    }
    if (!response.success) {
      HelperMethods.printDebug(
        '[Call panels] call read failed: ${response.error}',
      );
      return;
    }
    final rows = ((response.data as Map<String, dynamic>)['messages'] as List)
        .cast<Map<String, dynamic>>();
    final opened = <ChatMessage>[];
    final channelOf = <String, String>{};
    for (final row in rows) {
      final channelId = row['channel_id'];
      if (channelId is! String) continue;
      final message = await _open(row, channelId);
      if (message == null) continue;
      opened.add(message);
      channelOf[message.id] = channelId;
    }
    if (isClosed || generation != _generation || callId != _callChannel) {
      return;
    }
    _fromCall = opened;
    _fromCallChannel = channelOf;
    _publish();
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
    // Its new copy, or gone: a panel redrawn without the mark has ended, and
    // one read only through its call cannot be read at all once it has.
    List<ChatMessage> swap(List<ChatMessage> held) => [
      for (final m in held)
        if (m.id != messageId) m else ?message,
    ];
    final held = _byChannel[channelId];
    if (held != null) _byChannel[channelId] = swap(held);
    _fromCall = swap(_fromCall);
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
    // One copy of each: a channel the caller reads and the call both answer
    // with a player posted there.
    void add(ChatMessage message, String channelId) {
      if (channelOf.containsKey(message.id)) return;
      channelOf[message.id] = channelId;
      all.add(message);
    }

    for (final MapEntry(key: channelId, value: rows) in _byChannel.entries) {
      for (final message in LiveItems.callPanels(rows, callUserIds: _callIds)) {
        add(message, channelId);
      }
    }
    for (final message in LiveItems.callPanels(
      _fromCall,
      callUserIds: _callIds,
    )) {
      final channelId = _fromCallChannel[message.id];
      if (channelId != null) add(message, channelId);
    }
    all.sort(
      (a, b) => (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0),
    );
    emit(CallPanelsState(panels: all, channelOf: channelOf));
  }

  // ── Doorbells ─────────────────────────────────────────────

  /// Hold the server's topic, where an open channel's doorbells ring, each
  /// private channel's own, and a private call's, where its players' ring.
  /// Reconciled when the server's list or the call moves.
  void _syncFeeds() {
    final server = _session.serverById(_serverId);
    if (isClosed || server == null || _callIds.isEmpty) return;
    final wanted = {
      ServerTopics.server(server.id),
      for (final channel in server.channels)
        if (channel.isPrivate &&
            (channel.channelType == ChannelType.text ||
                channel.id == _callChannel))
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

  /// A bot in the call posted: its channel, or the call, may have a new
  /// player. A channel the caller cannot read is the call's to answer.
  void _onMessage(Map<String, dynamic> message) {
    final channelId = BroadcastPayload.stringOf(message, 'channel_id');
    final sender = BroadcastPayload.stringOf(message, 'sender_id');
    if (channelId == null || !_callIds.contains(sender)) return;
    final server = _session.serverById(_serverId);
    if (server != null && _textChannels(server).contains(channelId)) {
      unawaited(_readChannel(channelId));
    }
    unawaited(_readCall());
  }

  void _onMessageChanged(Map<String, dynamic> message) {
    final channelId = BroadcastPayload.stringOf(message, 'channel_id');
    final messageId = BroadcastPayload.stringOf(message, 'message_id');
    if (channelId == null || messageId == null) return;
    final held =
        (_byChannel[channelId]?.any((m) => m.id == messageId) ?? false) ||
        _fromCall.any((m) => m.id == messageId);
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
