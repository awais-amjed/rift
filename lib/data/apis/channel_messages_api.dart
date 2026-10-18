import '../classes/api_response.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

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
