import '../classes/api_response.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// A channel's messages on a server: sending, editing, deleting and paging
/// sealed envelopes. Pass-throughs — all crypto happens in the chat cubit and
/// `CryptoRepository`.
///
/// Everything acts on the selected server except a send and a delete, which
/// can name one. A forward's destination is routinely on another server, and
/// a report is acted on from its own server's page.
///
/// Holds nothing, so a widget that needs one builds it from the session.
class ChannelMessagesApi {
  final SessionRepository _session;

  ChannelMessagesApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// [call] against the selected server.
  Future<APIResponse> _onSelected(
    Future<APIResponse> Function(Server server, String token) call,
  ) async {
    final server = _session.selectedServer;
    if (server == null) return APIResponse.error(_session.noTarget(null));
    return _session.callFor(server, (token) => call(server, token));
  }

  /// [call] against [serverId], or the selected server, with that server's
  /// key.
  ///
  /// A server with no key yet is refused here rather than sent an empty one:
  /// an envelope sealed for one server must not land anywhere else, and
  /// resolving the server once for both halves is what keeps them agreeing.
  Future<APIResponse> _onNamed(
    String? serverId,
    Future<APIResponse> Function(Server server, String anonKey, String token)
    call,
  ) async {
    final server = _session.target(serverId);
    final anonKey = server?.supabaseKey;
    if (server == null || anonKey == null) {
      return APIResponse.error(_session.noTarget(serverId));
    }
    return _session.callFor(server, (token) => call(server, anonKey, token));
  }

  /// Store one E2E message envelope for [channelId] on [serverId], or the
  /// selected server.
  Future<APIResponse> sendChatMessage({
    required String channelId,
    required Map<String, dynamic> envelope,
    List<String> mentions = const [],
    bool mentionsAll = false,
    String? toBot,
    Map<String, dynamic>? poll,
    String? serverId,
  }) => _onNamed(
    serverId,
    (server, anonKey, token) => _repository.sendMessage(
      server.supabaseUrl,
      anonKey: anonKey,
      channelId: channelId,
      envelope: envelope,
      mentions: mentions,
      mentionsAll: mentionsAll,
      toBot: toBot,
      poll: poll,
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
  }) => _onSelected(
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
  }) => _onSelected(
    (server, token) => _repository.editMessage(
      server.supabaseUrl,
      anonKey: server.supabaseKey ?? '',
      messageId: messageId,
      envelope: envelope,
      bearerToken: token,
    ),
  );

  /// Hard-delete one channel message (sender, or a moderator) on [serverId],
  /// or the selected server.
  Future<APIResponse> deleteChatMessage({
    required int messageId,
    String? serverId,
  }) => _onNamed(
    serverId,
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
  }) => _onSelected(
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

  /// Re-read one channel message after a change doorbell named it. Answers
  /// `{message: …}`, or `{message: null}` when the row has been deleted.
  Future<APIResponse> getChatMessage({
    required String channelId,
    required int messageId,
  }) => _onSelected(
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
