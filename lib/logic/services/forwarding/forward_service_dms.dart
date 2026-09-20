part of 'forward_service.dart';

/// Forwarding into a direct conversation, on a server or on central.
///
/// Both derive their key the same way — X25519 between the two chat
/// identities on that host — so the only thing that differs is which host,
/// which client, and where the blobs go. Written together for that reason:
/// the two drifting apart is how a message ends up sealed with central's
/// identity and posted to a server.
mixin _ForwardDmsMixin on _ForwardBlobsMixin {
  VaultCubit get vault;
  CryptoRepository get crypto;

  Future<ServerIdentity?> _identityFor(Server server);

  Future<String?> _sendToServerDm(
    ServerDmTarget target,
    ForwardedMessage message,
    List<Uint8List?> bytes,
    String? note,
  ) async {
    final server = target.server;
    final me = server.user?.id;
    final peerKey = target.peerChatPublicKey;
    if (me == null) return 'You are not signed in to ${server.name}.';
    if (peerKey == null) {
      return '${target.peerName} has not published a key on ${server.name}.';
    }

    final host = Uri.parse(server.supabaseUrl).host;
    final key = await _dmKey(host, peerKey);
    final identity = await _identityFor(server);
    if (key == null || identity == null) return 'Your vault is locked.';

    final context = MessageEnvelope.conversationContext(me, target.peerId);
    final attachments = await _reupload(
      message.attachments,
      bytes,
      // The same scope the DM's own uploads use: colons are not legal in a
      // storage path, and the sweep matches on this exact spelling.
      scopePrefix: context.replaceAll(':', '_'),
      serverId: server.id,
    );

    final envelope = await crypto.sealMessage(
      plaintext: MessageBody(
        text: note ?? '',
        forwarded: message.withAttachments(attachments),
      ).encode(),
      messageKey: key,
      signingKeyPair: identity.keyPair,
      contextId: context,
      keyVersion: 1,
    );

    final response = await servers.sendDm(
      recipientId: target.peerId,
      envelope: envelope.toJson(),
      serverId: server.id,
    );
    return response.success ? null : (response.error?.toString() ?? 'Failed');
  }

  Future<String?> _sendToCentralDm(
    CentralDmTarget target,
    ForwardedMessage message,
    List<Uint8List?> bytes,
    String? note,
  ) async {
    final me = central.currentUser?.id;
    final peerKey = target.peerChatPublicKey;
    if (me == null) return 'You are not signed in to Rift.';
    if (peerKey == null) return '@${target.peerHandle} has no key published.';
    if (vault.state.masterSeed == null) return 'Your vault is locked.';

    final host = Uri.parse(SupabaseConfig.supabaseUrl).host;
    final key = await _dmKey(host, peerKey);
    final identity = await vault.getIdentityForHost(host);
    if (key == null) return 'Your vault is locked.';

    // Central files a member's blobs under their own id, not the pair: the
    // bucket is shared by everybody on the tier and the folder is what the
    // policy scopes writes by.
    final attachments = await _reupload(
      message.attachments,
      bytes,
      scopePrefix: me,
    );

    final envelope = await crypto.sealMessage(
      plaintext: MessageBody(
        text: note ?? '',
        forwarded: message.withAttachments(attachments),
      ).encode(),
      messageKey: key,
      signingKeyPair: identity.keyPair,
      contextId: MessageEnvelope.conversationContext(me, target.peerId),
      keyVersion: 1,
    );

    final response = await central.sendDm(
      recipientId: target.peerId,
      envelope: envelope.toJson(),
    );
    if (response.success) return null;
    return _centralRefusal(response);
  }

  Future<Uint8List?> _dmKey(String host, String peerChatPublicKey) async {
    if (vault.state.masterSeed == null) return null;
    final identity = await vault.getChatIdentityForHost(host);
    return crypto.deriveDmKey(
      myKeyPair: identity.keyPair,
      theirPublicKey: CryptoRepository.fromBase64(peerChatPublicKey),
    );
  }

  /// Central's refusals are bare codes. The two a forward can actually hit
  /// are worth a sentence; the rest keep whatever central said.
  static String _centralRefusal(APIResponse response) =>
      switch (response.errorCode) {
        'quota_exceeded' => 'You have used up today\'s message allowance.',
        'not_friends' => 'You can only message people you are friends with.',
        _ => response.error?.toString() ?? 'Failed',
      };
}
