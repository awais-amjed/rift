part of 'server_cubit.dart';

/// Chat API wrappers (E2E messaging). Thin pass-throughs to the repository —
/// all crypto happens in ChannelChatCubit/CryptoRepository; these only add
/// token auto-refresh and server resolution.
mixin _ServerChatApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Publish the local user's X25519 chat public key (idempotent).
  Future<APIResponse> publishChatKey(String chatPublicKey) =>
      _callWithAutoRefresh(
        (token) => _repository.publishChatKey(
          state.selectedServer!.supabaseUrl,
          chatPublicKey: chatPublicKey,
          bearerToken: token,
        ),
      );

  /// Store one E2E message envelope for [channelId].
  Future<APIResponse> sendChatMessage({
    required String channelId,
    required Map<String, dynamic> envelope,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.sendMessage(
          state.selectedServer!.supabaseUrl,
          channelId: channelId,
          envelope: envelope,
          bearerToken: token,
        ),
      );

  /// Page through a channel's message envelopes.
  Future<APIResponse> listChatMessages({
    required String channelId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.listMessages(
          state.selectedServer!.supabaseUrl,
          channelId: channelId,
          beforeId: beforeId,
          afterId: afterId,
          limit: limit,
          bearerToken: token,
        ),
      );

  /// Fetch my sealed channel keys + current version + healing set.
  Future<APIResponse> getChannelKey(String channelId) =>
      _callWithAutoRefresh(
        (token) => _repository.getChannelKey(
          state.selectedServer!.supabaseUrl,
          channelId: channelId,
          bearerToken: token,
        ),
      );

  /// List key-distribution work available to the local user.
  Future<APIResponse> sweepChannelKeys() => _callWithAutoRefresh(
        (token) => _repository.sweepChannelKeys(
          state.selectedServer!.supabaseUrl,
          bearerToken: token,
        ),
      );

  /// Store one E2E DM envelope for [recipientId].
  Future<APIResponse> sendDm({
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.sendDm(
          state.selectedServer!.supabaseUrl,
          recipientId: recipientId,
          envelope: envelope,
          bearerToken: token,
        ),
      );

  /// Page through the DM conversation with [peerId].
  Future<APIResponse> listDms({
    required String peerId,
    int? beforeId,
    int? afterId,
    int? limit,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.listDms(
          state.selectedServer!.supabaseUrl,
          peerId: peerId,
          beforeId: beforeId,
          afterId: afterId,
          limit: limit,
          bearerToken: token,
        ),
      );

  /// List DM conversations for the local user.
  Future<APIResponse> listDmConversations() => _callWithAutoRefresh(
        (token) => _repository.listDmConversations(
          state.selectedServer!.supabaseUrl,
          bearerToken: token,
        ),
      );

  /// Store sealed keyring entries for a key version.
  Future<APIResponse> postChannelKeys({
    required String channelId,
    required int keyVersion,
    required List<Map<String, dynamic>> entries,
  }) =>
      _callWithAutoRefresh(
        (token) => _repository.postChannelKeys(
          state.selectedServer!.supabaseUrl,
          channelId: channelId,
          keyVersion: keyVersion,
          entries: entries,
          bearerToken: token,
        ),
      );
}
