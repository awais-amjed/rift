import '../classes/api_response.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// A channel's sealed keys on a server: publishing this member's chat key,
/// fetching what is sealed to it, and storing what it seals for others.
///
/// Pass-throughs. Every key is wrapped and unwrapped in `ChannelKeyring` and
/// the chat cubit's sweep; the server only ever holds sealed entries
/// (ARCHITECTURE.md §4).
///
/// Holds nothing, so a widget that needs one builds it from the session.
class ChannelKeysApi {
  final ServerSession _target;

  ChannelKeysApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Publish the local user's X25519 chat public key (idempotent).
  Future<APIResponse> publishChatKey(String chatPublicKey) => _target.call(
    (server, token) => _repository.publishChatKey(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      chatPublicKey: chatPublicKey,
      bearerToken: token,
    ),
  );

  /// Fetch my sealed channel keys + current version + healing set.
  Future<APIResponse> getChannelKey(String channelId) => _target.call(
    (server, token) => _repository.getChannelKey(
      server.supabaseUrl,
      channelId: channelId,
      bearerToken: token,
    ),
  );

  /// List key-distribution work available to the local user.
  Future<APIResponse> sweepChannelKeys() => _target.call(
    (server, token) =>
        _repository.sweepChannelKeys(server.supabaseUrl, bearerToken: token),
  );

  /// Store sealed keyring entries for a key version — a new one when [mint],
  /// with the [link] that opens the version before it.
  Future<APIResponse> postChannelKeys({
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
    required bool mint,
    ({String ciphertext, String nonce})? link,
  }) => _target.call(
    (server, token) => _repository.postChannelKeys(
      server.supabaseUrl,
      channelId: channelId,
      keyVersion: keyVersion,
      entries: entries,
      mint: mint,
      link: link,
      bearerToken: token,
    ),
  );

  /// Drop our own keyring rows the channel's links already cover.
  Future<APIResponse> pruneChannelKeys(String channelId, List<int> versions) =>
      _target.call(
        (server, token) => _repository.pruneChannelKeys(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
          channelId: channelId,
          versions: versions,
        ),
      );
}
