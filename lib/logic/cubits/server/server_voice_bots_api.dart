part of 'server_cubit.dart';

/// What a bot may *hear* — the voice half of BOTS.md §6.
///
/// Its own file rather than more of [_ServerBotsApiMixin], because the two
/// grants are not the same promise and the code should not suggest they are.
///
/// A channel key is arithmetic: revoking rotates forward, and nothing can
/// unread what has already been read. That is why the dialog next door warns on
/// the way *in*. Hearing a call is a permission on a LiveKit token — voice is
/// not end-to-end encrypted (ARCHITECTURE.md §5) — so revoking pushes
/// `canSubscribe: false` onto the live connection and the audio stops mid-call.
///
/// The default is the part worth stating: **a bot publishes and hears nothing**
/// unless somebody granted it this, per channel. A music bot never needs it.
mixin _ServerVoiceBotsApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  String get _anonKey;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Let [botId] hear [channelId], or stop it.
  Future<({bool success, String? error})> setBotVoiceListen({
    required String channelId,
    required String botId,
    required bool listen,
  }) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server');

    final response = await _callWithAutoRefresh(
      (token) => _repository.setBotVoiceListen(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        channelId: channelId,
        botId: botId,
        listen: listen,
      ),
    );
    if (!response.success) {
      return (success: false, error: response.error ?? 'Could not do that');
    }
    return (success: true, error: null);
  }

  /// Ask [botId] into [channelId], or send it away (`summon_bot_to_voice`).
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
  Future<({bool success, String? error})> setBotVoiceSummon({
    required String channelId,
    required String botId,
    required bool summon,
  }) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server');

    final response = await _callWithAutoRefresh(
      (token) => _repository.setBotVoiceSummon(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        channelId: channelId,
        botId: botId,
        summon: summon,
      ),
    );
    if (!response.success) {
      return (success: false, error: response.error ?? 'Could not do that');
    }
    return (success: true, error: null);
  }

  /// Seal one bot its media key for [channelId].
  ///
  /// The bytes are produced by [ChannelKeyring], which holds the channel key;
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
    final server = state.selectedServer;
    final me = server?.user?.id;
    if (server == null || me == null) return;

    await _callWithAutoRefresh(
      (token) => _repository.postBotVoiceKey(
        server.supabaseUrl,
        anonKey: _anonKey,
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

  /// Who can hear each voice channel on this server: channel id → bot names.
  ///
  /// The whole server in one call, because the sidebar draws every voice
  /// channel at once and a query per row would be a query per row.
  Future<Map<String, List<String>>> voiceListenersByChannel() async {
    final rows = await _voiceListenerRows(null);
    final byChannel = <String, List<String>>{};
    for (final row in rows) {
      (byChannel[row['channel_id'] as String] ??= []).add(
        (row['bot_name'] as String?) ?? 'a bot',
      );
    }
    return byChannel;
  }

  /// Bots summoned into each voice channel, by name (`bot_voice_summons`).
  ///
  /// The same one round trip as [voiceListenersByChannel] and deliberately a
  /// separate one: they answer different questions and a client draws them
  /// differently. A listener is somebody else hearing the room; a summon is a
  /// bot that was asked in and may not have arrived yet.
  Future<Map<String, List<({String id, String name})>>>
  voiceSummonsByChannel() async {
    final server = state.selectedServer;
    if (server == null) return const {};

    final response = await _callWithAutoRefresh(
      (token) => _repository.listVoiceSummons(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
      ),
    );
    if (!response.success) return const {};

    final rows =
        ((response.data as Map<String, dynamic>)['summons'] as List? ??
                const [])
            .cast<Map<String, dynamic>>();
    final byChannel = <String, List<({String id, String name})>>{};
    for (final row in rows) {
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
  Future<Set<String>> voiceListenerIds(String channelId) async {
    final rows = await _voiceListenerRows(channelId);
    return {for (final row in rows) row['bot_id'] as String};
  }

  /// The voice channels [botId] can hear.
  ///
  /// Filtered client-side off the whole-server read rather than asked for by
  /// bot, because this is the same one round trip the sidebar already makes and
  /// the table has one row per grant — which is a number of rows an admin typed
  /// in by hand, one at a time.
  Future<Set<String>> voiceChannelsHeardBy(String botId) async {
    final rows = await _voiceListenerRows(null);
    return {
      for (final row in rows)
        if (row['bot_id'] == botId) row['channel_id'] as String,
    };
  }

  Future<List<Map<String, dynamic>>> _voiceListenerRows(
    String? channelId,
  ) async {
    final server = state.selectedServer;
    if (server == null) return const [];

    final response = await _callWithAutoRefresh(
      (token) => _repository.listVoiceListeners(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        channelId: channelId,
      ),
    );
    if (!response.success) return const [];

    return ((response.data as Map<String, dynamic>)['listeners'] as List? ??
            const [])
        .cast<Map<String, dynamic>>();
  }
}
