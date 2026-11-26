import 'package:rift_crypto/rift_crypto.dart';

import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// What a bot may *hear*, and which bots were asked into a call — the voice
/// half of BOTS.md §6.
///
/// Its own class rather than more of the bot calls, because the two grants
/// are not the same promise and the code should not suggest they are.
///
/// A channel key is arithmetic: revoking rotates forward, and nothing can
/// unread what has already been read. That is why the dialog next door warns
/// on the way *in*. Hearing a call is a permission on a LiveKit token — voice
/// is not end-to-end encrypted (ARCHITECTURE.md §5) — so revoking pushes
/// `canSubscribe: false` onto the live connection and the audio stops
/// mid-call.
///
/// The default is the part worth stating: **a bot publishes and hears
/// nothing** unless somebody granted it this, per channel. A music bot never
/// needs it.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class VoiceBotsApi {
  final ServerSession _target;

  VoiceBotsApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Let [botId] hear [channelId], or stop it.
  ///
  /// [stillConnected] is a change saved that the voice server was not told:
  /// a bot in the call keeps hearing (or not) on the token it holds until it
  /// leaves, up to that token's hour.
  Future<({bool success, String? error, bool stillConnected})>
  setBotVoiceListen({
    required String channelId,
    required String botId,
    required bool listen,
  }) async {
    final server = _target.server;
    if (server == null) {
      return (success: false, error: 'No server', stillConnected: false);
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.setBotVoiceListen(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        botId: botId,
        listen: listen,
      ),
    );
    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Could not do that',
        stillConnected: false,
      );
    }
    return (
      success: true,
      error: null,
      stillConnected: _liveKitMissed(response.data),
    );
  }

  /// Ask [botId] into [channelId] (`summon_bot_to_voice`).
  ///
  /// Distinct from [setBotVoiceListen] in the way that matters: this one is
  /// `SUMMON_BOTS`, which `@everyone` holds, because a summoned bot publishes
  /// and cannot hear. Asking the music bot to play is not the same decision as
  /// letting a program listen to the room, and it should not need the same
  /// permission or the same warning.
  ///
  /// Failure is returned rather than thrown and the caller may ignore it: a
  /// summon that did not land means the bot does not turn up, which is a thing
  /// somebody can see and try again, not a reason to fail the message that
  /// carried it.
  ///
  /// [needsKey] is the bot still owed a media key here, which members in the
  /// call seal when told to. A repeat summon of a bot already keyed needs
  /// nobody, and every `/play` in a queue used to ring the whole server. An
  /// older server does not say, and is read as needing one.
  Future<({bool success, String? error, bool needsKey})> summonBot({
    required String channelId,
    required String botId,
  }) async {
    final server = _target.server;
    if (server == null) {
      return (success: false, error: ServerSession.gone, needsKey: false);
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.summonBotToVoice(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        botId: botId,
      ),
    );
    final data = response.data;
    final answer = data is Map ? data : const {};
    final refused = response.success
        ? _summonRefusal(answer['reason'] as String?)
        : (response.error ?? 'Could not do that');
    if (refused != null) {
      return (success: false, error: refused, needsKey: false);
    }
    return (success: true, error: null, needsKey: answer['needs_key'] != false);
  }

  /// The RPC's `reason` put into words, or null for `ok`.
  static String? _summonRefusal(String? reason) => switch (reason) {
    'ok' => null,
    'forbidden' => 'Not allowed to summon bots',
    'no_such_channel' => 'Channel not found',
    'not_a_voice_channel' => 'That is not a voice channel',
    'no_such_bot' => 'Bot not found',
    _ => 'Could not call the bot in',
  };

  /// Send [botId] away from [channelId] (`dismiss_bot_from_voice`, through
  /// `set_bot_voice_summon`, which also drops it from the live room).
  ///
  /// [stillConnected] is a bot sent away that the voice server did not drop:
  /// it cannot come back, but plays on until it leaves by itself.
  Future<({bool success, String? error, bool stillConnected})> dismissBot({
    required String channelId,
    required String botId,
  }) async {
    final server = _target.server;
    if (server == null) {
      return (success: false, error: ServerSession.gone, stillConnected: false);
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.setBotVoiceSummon(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        botId: botId,
        summon: false,
      ),
    );
    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Could not do that',
        stillConnected: false,
      );
    }
    return (
      success: true,
      error: null,
      stillConnected: _liveKitMissed(response.data),
    );
  }

  /// Seal one bot its media key for [channelId].
  ///
  /// The bytes are produced by `ChannelKeyring`, which holds the channel key;
  /// this only posts them. Failure is swallowed by the caller on purpose — a
  /// bot short of a key is inaudible until the next member opens the call, and
  /// that is not worth failing somebody's own join over.
  Future<void> postBotVoiceKey({
    required String channelId,
    required String botId,
    required int keyVersion,
    required bool isChannelKey,
    required WrappedKey wrapped,
  }) async {
    final server = _target.server;
    final me = server?.user?.id;
    if (server == null || me == null) return;

    await _session.callFor(
      server,
      (token) => _repository.postBotVoiceKey(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        botId: botId,
        keyVersion: keyVersion,
        isChannelKey: isChannelKey,
        wrapped: wrapped.toJson(),
        wrappedBy: me,
      ),
    );
  }

  /// Who can hear each voice channel on this server: channel id → bots.
  ///
  /// The whole server in one call, because the sidebar draws every voice
  /// channel at once and a query per row would be a query per row.
  ///
  /// Null when the read failed, which is not "nobody listens".
  ///
  /// [first] is a first load on the server, which may share one
  /// `server_start` with the other features opening it (`ServerStartShare`).
  Future<Map<String, List<({String id, String name})>>?>
  voiceListenersByChannel({bool first = false}) async {
    final rows = await _voiceListenerRows(null, first: first);
    return rows == null ? null : _byChannel(rows);
  }

  /// Bots summoned into each voice channel, by name (`bot_voice_summons`).
  ///
  /// The same one round trip as [voiceListenersByChannel] and deliberately a
  /// separate one: they answer different questions and a client draws them
  /// differently. A listener is somebody else hearing the room; a summon is a
  /// bot that was asked in and may not have arrived yet.
  ///
  /// Null when the read failed. [first] as [voiceListenersByChannel].
  Future<Map<String, List<({String id, String name})>>?> voiceSummonsByChannel({
    bool first = false,
  }) async {
    final server = _target.server;
    if (server == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _repository.listVoiceSummons(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        first: first,
      ),
    );
    if (!response.success) return null;

    return _byChannel((response.data as Map<String, dynamic>)['summons']);
  }

  /// [voiceListenersByChannel] and [voiceSummonsByChannel] in one read
  /// (`voice_bots`, self-host 084), for a `voice_bots` ring. Null from a
  /// server before it, which is then asked them apart; null parts are a
  /// failed read, as there.
  Future<
    ({
      Map<String, List<({String id, String name})>>? listeners,
      Map<String, List<({String id, String name})>>? summons,
    })?
  >
  voiceBotsByChannel() async {
    final server = _target.server;
    if (server == null) return (listeners: null, summons: null);
    final response = await _session.callFor(
      server,
      (token) => _repository.listVoiceBots(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (response.errorCode == 'PGRST202') return null;
    if (!response.success) return (listeners: null, summons: null);
    final data = response.data as Map<String, dynamic>;
    return (
      listeners: _byChannel(data['listeners']),
      summons: _byChannel(data['summons']),
    );
  }

  /// Rows of `{channel_id, bot_id, bot_name}`, by channel.
  static Map<String, List<({String id, String name})>> _byChannel(
    Object? rows,
  ) {
    final byChannel = <String, List<({String id, String name})>>{};
    for (final row in ((rows as List?) ?? const []).cast<Map>()) {
      (byChannel[row['channel_id'] as String] ??= []).add((
        id: row['bot_id'] as String,
        name: (row['bot_name'] as String?) ?? 'a bot',
      ));
    }
    return byChannel;
  }

  /// The ids of the bots that can hear [channelId] — for the dialog that
  /// changes them, where [voiceListenersByChannel] is names for the marker
  /// every member reads.
  /// Null when the read failed.
  Future<Set<String>?> voiceListenerIds(String channelId) async {
    final rows = await _voiceListenerRows(channelId);
    if (rows == null) return null;
    return {for (final row in rows) row['bot_id'] as String};
  }

  /// The voice channels [botId] can hear.
  ///
  /// Filtered client-side off the whole-server read rather than asked for by
  /// bot, because this is the same one round trip the sidebar already makes
  /// and the table has one row per grant — which is a number of rows an admin
  /// typed in by hand, one at a time.
  ///
  /// Null when the read failed: the dialog deciding on a grant must not read
  /// that as "hears nothing".
  Future<Set<String>?> voiceChannelsHeardBy(String botId) async {
    final rows = await _voiceListenerRows(null);
    if (rows == null) return null;
    return {
      for (final row in rows)
        if (row['bot_id'] == botId) row['channel_id'] as String,
    };
  }

  /// Null when the read failed.
  Future<List<Map<String, dynamic>>?> _voiceListenerRows(
    String? channelId, {
    bool first = false,
  }) async {
    final server = _target.server;
    if (server == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _repository.listVoiceListeners(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        first: first,
      ),
    );
    if (!response.success) return null;

    return ((response.data as Map<String, dynamic>)['listeners'] as List? ??
            const [])
        .cast<Map<String, dynamic>>();
  }

  /// Whether the server saved the change but could not reach LiveKit to put
  /// it on the live connection (`livekit_error` in its answer).
  static bool _liveKitMissed(Object? data) =>
      data is Map && data['livekit_error'] != null;
}
