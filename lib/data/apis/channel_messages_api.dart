import '../classes/api_response.dart';
import '../classes/server.dart';
import '../classes/server_member.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';
import 'bot_keys_api.dart';

/// What a channel showed when it opened, in the answers of the reads
/// `channel_open` stands for: [page] as [ChannelMessagesApi.listChatMessages]
/// answers, [live] as `listLiveMessages`, [key] as `getChannelKey`, the
/// [listeners] as `BotKeysApi.channelListeners` and the [bots] as
/// `MembersApi.listBots`. Null [listeners] is a failed read, as there; null
/// [bots] is one to read whole, failed or longer than a page.
typedef ChannelOpening = ({
  APIResponse page,
  APIResponse live,
  APIResponse key,
  List<String>? listeners,
  List<ServerMember>? bots,
});

/// A channel's messages on a server: sending, editing, deleting and paging
/// sealed envelopes. Pass-throughs — all crypto happens in the chat cubit and
/// `CryptoRepository`.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class ChannelMessagesApi {
  final ServerSession _target;

  ChannelMessagesApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// [call] against the server, with its key.
  ///
  /// A server with no key yet is refused here rather than sent an empty one:
  /// an envelope sealed for one server must not land anywhere else, and
  /// resolving the server once for both halves is what keeps them agreeing.
  Future<APIResponse> _onNamed(
    Future<APIResponse> Function(Server server, String anonKey, String token)
    call,
  ) async {
    final server = _target.server;
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) {
      return APIResponse.error(ServerSession.gone);
    }
    return _session.callFor(server, (token) => call(server, anonKey, token));
  }

  /// Store one E2E message envelope for [channelId].
  Future<APIResponse> sendChatMessage({
    required String channelId,
    required Map<String, dynamic> envelope,
    List<String> mentions = const [],
    bool mentionsAll = false,
    String? toBot,
    Map<String, dynamic>? poll,
    List<String> attachmentPaths = const [],
  }) => _onNamed(
    (server, anonKey, token) => _repository.sendMessage(
      server.supabaseUrl,
      anonKey: anonKey,
      channelId: channelId,
      envelope: envelope,
      mentions: mentions,
      mentionsAll: mentionsAll,
      toBot: toBot,
      poll: poll,
      attachmentPaths: attachmentPaths,
      bearerToken: token,
    ),
  );

  /// Press something on a bot's panel.
  Future<APIResponse> sendPanelAction({
    required String channelId,
    required Map<String, dynamic> envelope,
    required String toBot,
    required int replyTo,
    required String actionId,
    String? actionValue,
  }) => _target.call(
    (server, token) => _repository.sendPanelAction(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      channelId: channelId,
      envelope: envelope,
      toBot: toBot,
      replyTo: replyTo,
      actionId: actionId,
      actionValue: actionValue,
      bearerToken: token,
    ),
  );

  /// Replace one channel message's envelope (sender only).
  Future<APIResponse> editChatMessage({
    required int messageId,
    required Map<String, dynamic> envelope,
  }) => _target.call(
    (server, token) => _repository.editMessage(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      messageId: messageId,
      envelope: envelope,
      bearerToken: token,
    ),
  );

  /// Hard-delete one channel message (sender, or a moderator).
  Future<APIResponse> deleteChatMessage({required int messageId}) => _onNamed(
    (server, anonKey, token) => _repository.deleteMessage(
      server.supabaseUrl,
      anonKey: anonKey,
      messageId: messageId,
      bearerToken: token,
    ),
  );

  /// Page through a channel's message envelopes.
  Future<APIResponse> listChatMessages({
    required String channelId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) => _target.call(
    (server, token) => _repository.listMessages(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      channelId: channelId,
      beforeId: beforeId,
      afterId: afterId,
      limit: limit,
      bearerToken: token,
    ),
  );

  /// Everything [channelId] shows when it opens, in one request rather than
  /// five (self-host 066). Null from a server from before it, which is then
  /// read the old way.
  Future<ChannelOpening?> openChannel({
    required String channelId,
    int? limit,
  }) async {
    final response = await _target.call(
      (server, token) => _repository.openChannel(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        userId: server.user?.id ?? '',
        channelId: channelId,
        limit: limit,
        bearerToken: token,
      ),
    );
    if (response.errorCode == 'PGRST202') return null;
    if (!response.success) {
      return (
        page: response,
        live: response,
        key: response,
        listeners: null,
        bots: null,
      );
    }
    final data = response.data as Map<String, dynamic>;
    final keyError = data['key_error'] as String?;
    final bots = data['bots'] as Map<String, dynamic>;
    final serverId = _target.server?.id;
    return (
      page: APIResponse.success(data['page']),
      live: APIResponse.success(data['live']),
      key: keyError != null
          ? APIResponse(success: false, error: keyError, errorCode: keyError)
          : APIResponse.success(data['key']),
      listeners: BotKeysApi.listenerNames(data['listeners'] as List),
      bots: bots['has_more'] == true || serverId == null
          ? null
          : _session.members.remember(serverId, ServerMember.listFrom(bots)),
    );
  }

  /// The channel's open polls and live panels, for the bar above its
  /// message box. Answers `{messages: […]}`, shaped as a page is.
  Future<APIResponse> listLiveMessages({required String channelId}) =>
      _target.call(
        (server, token) => _repository.listLiveMessages(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          userId: server.user?.id ?? '',
          channelId: channelId,
          bearerToken: token,
        ),
      );

  /// The players of the bots in the voice call [callId], wherever each was
  /// posted. Answers `{messages: […]}`, each row with its own `channel_id`.
  Future<APIResponse> listCallLiveMessages({required String callId}) =>
      _target.call(
        (server, token) => _repository.listCallLiveMessages(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          userId: server.user?.id ?? '',
          callId: callId,
          bearerToken: token,
        ),
      );

  /// Everything the bar of the voice call [callId] can hold, in one read:
  /// its players and the live panels of every text channel the caller reads.
  /// Answers `{messages: […]}`, each row with its own `channel_id`, or
  /// `PGRST202` from a server from before it.
  Future<APIResponse> listCallPanels({required String callId}) => _target.call(
    (server, token) => _repository.listCallPanels(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      callId: callId,
      bearerToken: token,
    ),
  );

  /// Re-read one channel message after a change doorbell named it. Answers
  /// `{message: …}`, or `{message: null}` when the row has been deleted.
  Future<APIResponse> getChatMessage({
    required String channelId,
    required int messageId,
  }) => _target.call(
    (server, token) => _repository.getMessage(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      userId: server.user?.id ?? '',
      channelId: channelId,
      messageId: messageId,
      bearerToken: token,
    ),
  );
}
