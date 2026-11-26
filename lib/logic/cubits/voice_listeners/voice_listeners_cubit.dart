import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/apis/voice_bots_api.dart';
import '../../../data/classes/server.dart';
import '../../../data/repositories/session_repository.dart';
import '../../services/server_topic_watcher.dart';
import '../../services/server_topics.dart';

part 'voice_listeners_state.dart';

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Which bots can hear which of one server's voice channels, and which have
/// been called into one — for the markers in the sidebar.
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
class VoiceListenersCubit extends Cubit<VoiceBotsState> {
  final SessionRepository _session;
  late final ServerTopicWatcher _watcher;

  /// Counts reads, so only the newest one lands ([refresh]).
  int _reads = 0;

  VoiceListenersCubit({
    required SessionRepository session,
    required String serverId,
  }) : _session = session,
       super(const VoiceBotsState()) {
    _watcher = ServerTopicWatcher(
      session: session,
      watchedServerId: serverId,
      topicOf: (server) => ServerTopics.server(server.id),
      event: ServerEvent.voiceBots,
      onChanged: () => unawaited(refresh()),
      onServerChanged: _onServerChanged,
    );
  }

  /// The bots that can hear [channelId], by name. Empty is the common case and
  /// the one that draws nothing.
  List<String> listening(String channelId) => [
    for (final bot in state.listeners[channelId] ?? const <ListeningBot>[])
      bot.name,
  ];

  /// Whether [botId] may hear [channelId]. A bot in a call without it only
  /// speaks, and its row says so (`VoiceStatusIcon.cannotHear`).
  bool hears(String channelId, String botId) =>
      state.listeners[channelId]?.any((bot) => bot.id == botId) ?? false;

  /// The bots summoned into [channelId], whether or not they have turned up.
  List<SummonedBot> summoned(String channelId) =>
      state.summons[channelId] ?? const [];

  void _onServerChanged(Server? server) {
    // Clear first. Carrying grants read under an old session across would
    // put a recording light on a channel that may no longer have one, which
    // is the one direction this marker must never be wrong in.
    _reads++;
    emit(const VoiceBotsState());
    if (server != null) unawaited(refresh(first: true));
  }

  /// Re-read both. Called on server change, when the database says a grant
  /// or a summon came or went (`voice_bots`, whoever changed it), and by the
  /// client that changed one, which need not wait for the ring.
  ///
  /// One read where the server has `voice_bots` (self-host 084). Otherwise,
  /// and on the first read, which may share `server_start`, two started
  /// together: they are different tables and the sidebar wants them at the
  /// same moment, so serialising them would show a channel with its
  /// listeners and no summons for one frame.
  ///
  /// A read that fails keeps what is shown: an empty answer would take a
  /// bot's "can hear" marker down while it still hears, and nothing reads
  /// again until the next ring. Only the newest read lands, so one that was
  /// slow cannot put back what a later one has already moved past.
  ///
  /// [first] is the first read on the server, which may share one
  /// `server_start` with the server's other features opening.
  Future<void> refresh({bool first = false}) async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final read = ++_reads;
    final api = VoiceBotsApi(_session.on(serverId));
    final both = first ? null : await api.voiceBotsByChannel();
    final (listeners, summons) = both != null
        ? (both.listeners, both.summons)
        : await (
            api.voiceListenersByChannel(first: first),
            api.voiceSummonsByChannel(first: first),
          ).wait;
    if (isClosed || _watcher.serverId != serverId || read != _reads) return;
    emit(
      VoiceBotsState(
        listeners: listeners ?? state.listeners,
        summons: summons ?? state.summons,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _watcher.dispose();
    return super.close();
  }
}
