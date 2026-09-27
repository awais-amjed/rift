part of 'channel_chat_cubit.dart';

/// Pressing a button on a bot's panel.
///
/// Its own file rather than a corner of the send mixin, because it is not a
/// send. Nothing is sealed, nothing joins the conversation, and there is no
/// optimistic row to acknowledge, fail or retry — the three things the send
/// path is mostly made of. Splitting it out is also what got that file back
/// under its budget (CODE_STYLE §1).
mixin _ChannelChatPanelsMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  VaultCubit get _vaultCubit;
  CryptoRepository get _crypto;

  /// Press something on a bot's panel.
  ///
  /// Signed but not sealed, exactly like the command that would have done the
  /// same job before panels existed — the bot holds no channel key, so a sealed
  /// press is one it could not open. The channel sees the panel change and not
  /// the press: `is_interaction` keeps the row out of everybody else's view.
  ///
  /// Fire-and-forget, and deliberately without an optimistic anything. What
  /// the press *does* is entirely the bot's business — it may change the panel,
  /// or take a second, or decide not to — so a client guessing at the outcome
  /// would be guessing.
  Future<void> pressPanelAction(
    String messageId,
    String action,
    String? value,
  ) async {
    final channelId = state.channelId;
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    if (channelId == null || server == null || user == null) return;

    // The panel's author is the bot to answer. Taken from the row rather than
    // from anything the block carried: a button that named its own recipient
    // would let one bot's panel address another's.
    String? botId;
    for (final message in state.messages) {
      if (message.id == messageId) botId = message.authorId;
    }
    final replyTo = int.tryParse(messageId);
    if (botId == null || botId.isEmpty || replyTo == null) return;

    // The *server* identity, which is what signs a message — the chat identity
    // is X25519 and seals one.
    final identity = await _vaultCubit.getIdentityForHost(
      Uri.parse(server.supabaseUrl).host,
      serverId: server.id,
      version: server.keyVersion,
    );

    // The body is the action id rather than empty: it is what a client without
    // panels would show, and what the bot reads if it ignores `action_id`.
    final envelope = await _crypto.signPlaintext(
      plaintext: action,
      signingKeyPair: identity.keyPair,
      contextId: channelId,
    );

    final response = await _serverCubit.sendPanelAction(
      channelId: channelId,
      envelope: envelope.toJson(),
      toBot: botId,
      replyTo: replyTo,
      actionId: action,
      actionValue: value,
    );
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'That did not go');
    }
  }
}
