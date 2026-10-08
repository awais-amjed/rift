import '../classes/api_response.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// The one bot capability that is not arranged around a bot never holding a
/// key (BOTS.md §6).
///
/// Split from `WebhooksApi` because they are opposites wearing the same
/// shape: a webhook is a thing that can *write* into a channel without being a
/// member, and this is a thing that can *read* one. The second is the only
/// place in Rift where a decision cannot be undone — a key that has been
/// unwrapped stays unwrapped — so it keeps its own class and its own comments.
///
/// Holds nothing, so a widget builds one from the session.
class BotKeysApi {
  final SessionRepository _session;

  BotKeysApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// Hand a bot the key to a channel on the selected server, or take it back.
  ///
  /// Every rule behind this is in the database and none of it is repeated here
  /// — the permission, the channel being one the caller can see, the version
  /// the grant starts at, and the notice it leaves in the channel. What comes
  /// back is a reason, which is the only part a client has to translate.
  Future<({bool success, String? error})> setBotChannelKey({
    required String channelId,
    required String botId,
    required bool granted,
  }) async {
    final server = _session.selectedServer;
    if (server == null) return (success: false, error: _session.noTarget(null));

    final response = await _session.callFor(
      server,
      (token) => _repository.setBotChannelKey(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        botId: botId,
        granted: granted,
      ),
    );
    return _granted(response, also: 'already_granted');
  }

  /// Hand a bot every public channel, or take it all back.
  Future<({bool success, String? error})> setBotServerKey({
    required String botId,
    required bool granted,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (success: false, error: _session.noTarget(serverId));
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.setBotServerKey(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        botId: botId,
        granted: granted,
      ),
    );
    return _granted(response);
  }

  /// A grant's answer: `ok` (or [also]) is done, anything else is a reason.
  static ({bool success, String? error}) _granted(
    APIResponse response, {
    String? also,
  }) {
    if (!response.success) {
      return (success: false, error: response.error ?? 'Could not do that');
    }
    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok' && reason != also) {
      return (success: false, error: _grantFailure(reason as String?));
    }
    return (success: true, error: null);
  }

  static String _grantFailure(String? reason) => switch (reason) {
    'forbidden' => 'You cannot give bots access to channels here',
    'no_such_channel' => 'That channel is gone, or is not one you are in',
    'no_such_bot' => 'That bot is not on this server any more',
    _ => 'Could not change that bot’s access',
  };

  /// What one bot can read: the channels, and whether it is server-wide.
  Future<({Set<String> channelIds, bool serverWide})> botChannels(
    String botId, {
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) {
      return (channelIds: <String>{}, serverWide: false);
    }

    final response = await _session.callFor(
      server,
      (token) => _repository.listBotChannels(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        botId: botId,
      ),
    );
    if (!response.success) {
      return (channelIds: <String>{}, serverWide: false);
    }

    final data = response.data as Map<String, dynamic>;
    return (
      channelIds: {
        for (final id in (data['channel_ids'] as List? ?? const []))
          id as String,
      },
      serverWide: data['server_wide'] == true,
    );
  }

  /// The ids of the bots holding a key to [channelId] on the selected server.
  ///
  /// Separate from [channelListeners], which is the same query answered for a
  /// different audience: that one is names for a chip every member reads, this
  /// one is ids for the dialog that changes them.
  Future<Set<String>> channelListenerIds(String channelId) async {
    final rows = await _listeners(channelId);
    return {for (final r in rows) r['bot_id'] as String};
  }

  /// The bots holding a key to [channelId] on the selected server, by display
  /// name.
  ///
  /// Read on channel open and shown in the header, not behind a menu: a
  /// standing marker is the point (BOTS.md §6, rule 4). A dialog somebody has
  /// to go looking for tells the people who already knew.
  Future<List<String>> channelListeners(String channelId) async {
    final rows = await _listeners(channelId);
    return [
      for (final r in rows)
        (r['display_name'] as String?) ?? (r['username'] as String? ?? 'a bot'),
    ];
  }

  Future<List<Map<String, dynamic>>> _listeners(String channelId) async {
    final server = _session.selectedServer;
    if (server == null) return const [];

    final response = await _session.callFor(
      server,
      (token) => _repository.listChannelListeners(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
      ),
    );
    if (!response.success) return const [];

    final rows =
        (response.data as Map<String, dynamic>)['listeners'] as List? ??
        const [];
    return rows.cast<Map<String, dynamic>>();
  }
}
