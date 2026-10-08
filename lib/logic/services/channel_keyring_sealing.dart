part of 'channel_keyring.dart';

/// The half of a keyring that writes: bootstrapping a channel's first key, and
/// sealing it to everyone who is entitled to it and does not have it.
///
/// Split from the reading half because they are two jobs with two failure
/// modes. Reading is on the path of a member opening a channel and its failure
/// is *their* screen. Writing is a courtesy performed for other people — it
/// runs fire-and-forget, its failures cost somebody else a wait rather than
/// this client anything, and every one of them is swallowed on purpose.
mixin _KeyringSealingMixin {
  ChannelKeysApi get _channelKeys;
  VoiceBotsApi get _voiceBots;
  CryptoRepository get _crypto;
  void Function()? get onHealed;
  Map<int, Uint8List> get keys;

  /// Seal each bot the key it publishes with in this voice channel.
  ///
  /// A bot with no listening grant gets [VoiceKeys.forBot] — derived from the
  /// channel key, computable by every member, and not invertible by the bot. It
  /// can be heard and can hear nothing, which is the property a shared room key
  /// cannot express (BOTS.md §2).
  ///
  /// A bot that *has* been granted hearing gets the channel key itself, because
  /// there is no third thing to give it. That grant is a key grant with
  /// everything §6 says about one: it cannot be taken back, only rotated past.
  ///
  /// Best-effort and fire-and-forget, like healing. A bot short of a key is a
  /// bot nobody can hear until the next member opens the call, which is a
  /// nuisance; failing the caller's own join over it would be worse.
  Future<void> sealBotKeys(
    String channelId,
    int keyVersion,
    List<Map<String, dynamic>> bots,
  ) async {
    final channelKey = keys[keyVersion];
    if (channelKey == null) return;

    for (final bot in bots) {
      final botId = bot['bot_id'] as String?;
      final publicKey = bot['chat_public_key'] as String?;
      if (botId == null || publicKey == null) continue;

      try {
        final sealed = await VoiceKeys.forOneBot(
          crypto: _crypto,
          channelKey: channelKey,
          botId: botId,
          mayListen: bot['may_listen'] == true,
        );
        await _voiceBots.postBotVoiceKey(
          channelId: channelId,
          botId: botId,
          keyVersion: keyVersion,
          isChannelKey: sealed.isChannelKey,
          wrapped: await _crypto.wrapKey(
            key: sealed.key,
            recipientPublicKey: CryptoRepository.fromBase64(publicKey),
          ),
        );
      } catch (e) {
        HelperMethods.printDebug('[Keyring] bot key seal failed: $e');
      }
    }
  }

  /// Seal the current channel key to members who lack an entry. Conflicts are
  /// fine — another client healed them first.
  Future<void> healMembers(
    String channelId,
    int keyVersion,
    List<Map<String, dynamic>> members,
  ) async {
    final channelKey = keys[keyVersion];
    if (channelKey == null) return;
    try {
      final entries = await _crypto.sealKeyringEntries(
        key: channelKey,
        members: members,
      );
      final response = await _channelKeys.postChannelKeys(
        channelId: channelId,
        keyVersion: keyVersion,
        entries: entries,
        mint: false,
      );
      // Wake the healed members so their waiting screens refetch.
      if (response.success) onHealed?.call();
    } catch (e) {
      HelperMethods.printDebug('[Keyring] heal failed: $e');
    }
  }
}
