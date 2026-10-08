import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/apis/voice_bots_api.dart';
import '../../../data/classes/server.dart';
import '../../../data/repositories/session_repository.dart';
import '../../services/server_topic_watcher.dart';
import '../../services/server_topics.dart';
import '../server/server_cubit.dart';

/// One bot summoned into a voice channel.
typedef SummonedBot = ({String id, String name});

/// What the sidebar knows about bots and voice channels.
///
/// Two lists rather than one because they are two different facts. A listener
/// is somebody outside the room hearing it, which is a warning and is drawn as
/// one. A summon is a bot that was asked in — it publishes and cannot hear —
/// which is furniture, and is here mostly so one that never arrived can still
/// be seen and sent away.
class VoiceBotsState {
  /// Display names of the bots that can hear each channel.
  final Map<String, List<String>> listeners;

  /// Bots summoned into each channel, with the id needed to dismiss one.
  final Map<String, List<SummonedBot>> summons;

  const VoiceBotsState({this.listeners = const {}, this.summons = const {}});
}

/// Which bots can hear which voice channels, and which have been called into
/// one — for the markers in the sidebar.
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
  final VoiceBotsApi _api;
  late final ServerTopicWatcher _watcher;

  VoiceListenersCubit({
    required ServerCubit serverCubit,
    required SessionRepository session,
  }) : _api = VoiceBotsApi(session: session),
       super(const VoiceBotsState()) {
    // The one thing still read off the cubit: hearing the selection move.
    _watcher = ServerTopicWatcher(
      serverCubit: serverCubit,
      topicOf: (server) => ServerTopics.server(server.id),
      event: ServerEvent.voiceBots,
      onChanged: () => unawaited(refresh()),
      onServerChanged: _onServerChanged,
    );
  }

  /// The bots that can hear [channelId], by name. Empty is the common case and
  /// the one that draws nothing.
  List<String> listening(String channelId) =>
      state.listeners[channelId] ?? const [];

  /// The bots summoned into [channelId], whether or not they have turned up.
  List<SummonedBot> summoned(String channelId) =>
      state.summons[channelId] ?? const [];

  void _onServerChanged(Server? server) {
    // Clear first. Carrying the previous server's grants across a switch would
    // put a recording light on a channel that never had one, which is the one
    // direction this marker must never be wrong in.
    emit(const VoiceBotsState());
    if (server != null) unawaited(refresh());
  }

  /// Re-read both. Called on server change, when the database says a grant
  /// or a summon came or went (`voice_bots`, whoever changed it), and by the
  /// client that changed one, which need not wait for the ring.
  ///
  /// Two round trips, started together: they are different tables and the
  /// sidebar wants them at the same moment, so serialising them would show a
  /// channel with its listeners and no summons for one frame.
  Future<void> refresh() async {
    final (listeners, summons) = await (
      _api.voiceListenersByChannel(),
      _api.voiceSummonsByChannel(),
    ).wait;
    if (isClosed) return;
    emit(VoiceBotsState(listeners: listeners, summons: summons));
  }

  @override
  Future<void> close() async {
    await _watcher.dispose();
    return super.close();
  }
}
