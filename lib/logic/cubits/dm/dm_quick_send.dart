part of 'dm_cubit.dart';

/// Sending a server DM to somebody without opening the conversation: the
/// message box on a voice roster row's card, which lets a person write to
/// somebody in a call without leaving the call or the stream they watch.
///
/// Text only, sealed exactly as [sendDm] seals it. Into a conversation that is
/// already open it *is* [sendDm], so the open page draws the row the usual
/// way.
///
/// On the send mixin for [_sendAndSettle], whose outcome says whether a
/// message into the open conversation was stored or only held.
mixin _DmQuickSendMixin on Cubit<DmState>, _DmSendMixin {
  MembersApi get _members;
  Server? get _savedServer;
  String? get _seed;
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey);

  /// Sends [text] to [peerId]. Completes with what went wrong, in words, or
  /// null once the server has stored it.
  Future<String?> sendQuickDm({
    required String peerId,
    required String peerName,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (state.openPeerId == peerId && state.chatStatus == DmChatStatus.ready) {
      // Only stored is "sent": a message held as "Not sent" sits in a
      // conversation this card is not showing, and the card saying it went
      // was the one news of it.
      return switch (await _sendAndSettle(trimmed)) {
        _DmSendOutcome.sent => null,
        _DmSendOutcome.held =>
          'The message was not sent. It is kept in your conversation with '
              '$peerName.',
        _ => 'The message was not sent.',
      };
    }

    final server = _server;
    final user = server?.user;
    if (server == null || user == null) return 'Not signed in to this server.';

    // The member row carries their chat key: a roster row has only a name.
    final member = await _members.findMember(peerId);
    final key = await _dmKeyFor(peerId, member?.chatPublicKey);
    if (key == null) {
      return '$peerName has not enabled encrypted chat yet — they need to '
          'open the app once.';
    }

    try {
      final identity = await _vaultIdentityFor(server);
      final envelope = await _crypto.sealMessage(
        plaintext: MessageBody(text: trimmed).encode(),
        messageKey: key,
        signingKeyPair: identity.keyPair,
        contextId: DmCubit.conversationContext(user.id, peerId),
        keyVersion: 1,
      );
      final response = await _dms.sendDm(
        recipientId: peerId,
        envelope: envelope.toJson(),
      );
      if (!response.success) {
        return DmRefusal.describe(response.errorCode, peerName: peerName) ??
            response.error ??
            'The message was not sent.';
      }
    } catch (e) {
      HelperMethods.printDebug('[DM] quick send failed: $e');
      return 'The message was not sent.';
    }

    // The saved copy of this conversation, if there is one, was written
    // before this message and nothing here can add it: the send answers with
    // an id, not a row. Dropped, so the next open waits for the real page
    // rather than drawing one without it (`SavedConversation.noteSent`).
    final saved = _savedServer;
    final seed = _seed;
    if (saved != null && seed != null) {
      unawaited(
        MessageCache.instance.forget(
          seed,
          MessageCacheSlot.serverDm(
            supabaseUrl: saved.supabaseUrl,
            serverId: saved.id,
            peerId: peerId,
          ),
        ),
      );
    }
    unawaited(refreshConversations());
    return null;
  }
}
