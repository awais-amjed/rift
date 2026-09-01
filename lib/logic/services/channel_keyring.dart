import 'dart:async';
import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../../data/classes/server.dart';
import '../cubits/server/server_cubit.dart';
import '../cubits/vault/vault_cubit.dart';
import '../helper_methods.dart';
import 'chat_failure.dart';
import 'voice_keys.dart';

/// A channel's symmetric keys, fetched and unwrapped for this member.
///
/// Extracted from `ChannelChatCubit`, which was the only thing that needed one
/// while only text channels were encrypted. Voice needs the same key for the
/// same reason — LiveKit's frame cryptor takes raw bytes, and the bytes have to
/// be the ones every other member in the call already has.
///
/// **One implementation, deliberately.** Two copies of key bootstrap is two
/// things that can disagree about which version is current or how a race is
/// resolved, and the way that failure presents is a room where some people can
/// hear each other and some cannot. This class holds no opinion about what the
/// key is *for*.
///
/// Everything here is per channel and per member. The server stores only sealed
/// entries and can read none of them (ARCHITECTURE.md §4).
class ChannelKeyring {
  final ServerCubit _serverCubit;
  final VaultCubit _vaultCubit;
  final CryptoRepository _crypto;

  /// Called after this client seals the current key to members who lacked it,
  /// so their waiting screens refetch. Optional: a caller that has no doorbell
  /// to ring simply heals quietly.
  final void Function()? onHealed;

  ChannelKeyring({
    required ServerCubit serverCubit,
    required VaultCubit vaultCubit,
    required CryptoRepository crypto,
    this.onHealed,
  }) : _serverCubit = serverCubit,
       _vaultCubit = vaultCubit,
       _crypto = crypto;

  /// Unwrapped keys for the channel this ring was last loaded for, by version.
  final Map<int, Uint8List> keys = {};

  /// The newest version this client holds a key for. 0 means none yet.
  int currentVersion = 0;

  /// The key to seal with right now, or null while the ring is still empty.
  Uint8List? get currentKey => keys[currentVersion];

  /// Server ids whose chat public key we have published this run. Idempotent
  /// server-side; this only avoids a call per channel open.
  final Set<String> publishedChatKey = {};

  /// The master seed [publishedChatKey] is valid for — a vault reset in the
  /// same run yields a new identity whose key must be republished.
  String? _publishedChatKeySeed;

  void clear() {
    keys.clear();
    currentVersion = 0;
  }

  Future<ChatIdentity?> chatIdentity(Server server) async {
    if (_vaultCubit.state.masterSeed == null) return null;
    final host = Uri.parse(server.supabaseUrl).host;
    return _vaultCubit.getChatIdentityForHost(
      host,
      version: CryptoRepository.chatIdentityVersion,
    );
  }

  /// Publish our chat key if not done this run. Returns true when the server
  /// reports the key as newly published — the caller should then ring the
  /// key-sweep doorbell, because a newly keyed member is one nobody has sealed
  /// anything to yet.
  Future<bool> ensureChatKeyPublished(Server server) async {
    final seed = _vaultCubit.state.masterSeed;
    if (seed == null) return false;
    // The publish guard is per identity, not per app run: after a vault reset
    // + rejoin in the same run, the new user's key must still be published —
    // a stale guard here leaves the member unkeyed and unable to ever be
    // granted channel access (ISSUES.md #1).
    if (seed != _publishedChatKeySeed) {
      publishedChatKey.clear();
      _publishedChatKeySeed = seed;
    }
    if (publishedChatKey.contains(server.id)) return false;
    final identity = await chatIdentity(server);
    if (identity == null) return false;
    final response = await _serverCubit.publishChatKey(
      identity.publicKeyBase64,
    );
    if (!response.success) return false;
    publishedChatKey.add(server.id);
    final data = response.data as Map<String, dynamic>?;
    return data?['newly_published'] == true;
  }

  /// Pick up key versions minted since this channel was opened.
  ///
  /// Before rotation existed, a channel's current version could not change
  /// while you sat in it, so a client that already held a key had no reason to
  /// look again. A rotation breaks that: another member mints the next version
  /// and, until this client notices, it keeps sealing with a key the rest of
  /// the channel has moved off and cannot read what they send back.
  ///
  /// Deliberately additive, unlike [loadOrBootstrap], which clears the ring
  /// before refilling it. That is right when opening a channel and wrong here:
  /// this runs on a doorbell, against a client that is working, and a momentary
  /// network failure must not cost it the keys it already holds.
  Future<void> absorbNewVersions(String channelId) async {
    final server = _serverCubit.state.selectedServer;
    if (server == null) return;
    final identity = await chatIdentity(server);
    if (identity == null) return;

    final response = await _serverCubit.getChannelKey(channelId);
    if (!response.success) return;

    final data = response.data as Map<String, dynamic>;
    final version = data['current_version'] as int;
    if (version <= currentVersion) return;

    for (final entry
        in (data['my_keys'] as List).cast<Map<String, dynamic>>()) {
      final entryVersion = entry['key_version'] as int;
      if (keys.containsKey(entryVersion)) continue;
      try {
        keys[entryVersion] = await _crypto.unwrapKey(
          wrapped: WrappedKey.fromJson(entry),
          myKeyPair: identity.keyPair,
        );
      } catch (e) {
        HelperMethods.printDebug('[Keyring] unwrap failed: $e');
      }
    }

    // Only move up once the new key is actually in hand. Announcing a version
    // we cannot seal with would break sending outright, where staying put
    // leaves the client working until the rotation reaches it.
    if (keys.containsKey(version)) currentVersion = version;
  }

  /// Fetch + unwrap the keyring for [channelId]; bootstrap v1 when the channel
  /// has no key yet; heal members missing current-version entries.
  Future<KeyringOutcome> loadOrBootstrap(String channelId) async {
    clear();

    final server = _serverCubit.state.selectedServer;
    if (server == null) {
      return const KeyringOutcome.failed(ChatFailure.noServer());
    }
    final identity = await chatIdentity(server);
    if (identity == null) {
      return const KeyringOutcome.failed(ChatFailure.vaultLocked());
    }

    // Bootstrap can race another member: retry once on conflict, using the
    // winner's keyring.
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await _serverCubit.getChannelKey(channelId);
      if (!response.success) {
        return KeyringOutcome.failed(ChatFailure.fromResponse(response));
      }

      final data = response.data as Map<String, dynamic>;
      final version = data['current_version'] as int;
      final myKeys = (data['my_keys'] as List).cast<Map<String, dynamic>>();
      final missing = (data['members_missing'] as List)
          .cast<Map<String, dynamic>>();

      if (version == 0) {
        // No key yet — we're the bootstrapper (or we lose the race and loop).
        final bootstrapped = await _bootstrap(channelId, identity, missing);
        if (!bootstrapped.isWaiting) return bootstrapped;
        continue; // conflict — refetch the winner's keyring
      }

      // Unwrap every version sealed to us (full scrollback).
      for (final entry in myKeys) {
        try {
          keys[entry['key_version'] as int] = await _crypto.unwrapKey(
            wrapped: WrappedKey.fromJson(entry),
            myKeyPair: identity.keyPair,
          );
        } catch (e) {
          HelperMethods.printDebug('[Keyring] unwrap failed: $e');
        }
      }
      currentVersion = version;

      if (!keys.containsKey(version)) return const KeyringOutcome.waiting();

      // We hold the current key — heal anyone missing it (fire-and-forget).
      if (missing.isNotEmpty) {
        unawaited(healMembers(channelId, version, missing));
      }
      // And seal the media keys any bot in this call is short of. Same shape,
      // different key: a bot gets one derived from this one, so only somebody
      // holding this one can produce it (BOTS.md §6b).
      final bots = (data['bots_missing'] as List? ?? const [])
          .cast<Map<String, dynamic>>();
      if (bots.isNotEmpty) unawaited(sealBotKeys(channelId, version, bots));
      return const KeyringOutcome.ready();
    }
    // Both attempts hit the bootstrap race.
    return const KeyringOutcome.failed(ChatFailure.keyringConflict());
  }

  /// Generate v1 and seal it to every keyed member (including ourselves).
  Future<KeyringOutcome> _bootstrap(
    String channelId,
    ChatIdentity identity,
    List<Map<String, dynamic>> members,
  ) async {
    if (members.isEmpty) {
      return const KeyringOutcome.failed(ChatFailure.noKeyedMembers());
    }

    final channelKey = _crypto.generateChannelKey();
    final entries = await _crypto.sealKeyringEntries(
      key: channelKey,
      members: members,
    );

    final response = await _serverCubit.postChannelKeys(
      channelId: channelId,
      keyVersion: 1,
      entries: entries,
    );

    if (response.success) {
      keys[1] = channelKey;
      currentVersion = 1;
      return const KeyringOutcome.ready();
    }
    if (response.errorCode == 'keyring_conflict') {
      // Not a failure: the caller refetches the winner's ring.
      return const KeyringOutcome.waiting();
    }
    return KeyringOutcome.failed(ChatFailure.fromResponse(response));
  }

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
      final mayListen = bot['may_listen'] == true;

      try {
        final key = mayListen
            ? channelKey
            : await VoiceKeys.forBot(
                crypto: _crypto,
                channelKey: channelKey,
                botId: botId,
              );
        final wrapped = await _crypto.wrapKey(
          key: key,
          recipientPublicKey: CryptoRepository.fromBase64(publicKey),
        );
        await _serverCubit.postBotVoiceKey(
          channelId: channelId,
          botId: botId,
          keyVersion: keyVersion,
          isChannelKey: mayListen,
          wrapped: wrapped,
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
      final response = await _serverCubit.postChannelKeys(
        channelId: channelId,
        keyVersion: keyVersion,
        entries: entries,
      );
      // Wake the healed members so their waiting screens refetch.
      if (response.success) onHealed?.call();
    } catch (e) {
      HelperMethods.printDebug('[Keyring] heal failed: $e');
    }
  }
}

/// How a keyring load ended.
///
/// "Waiting" is not a failure: it is the state of a member who has joined a
/// channel nobody has sealed the current key to yet. Somebody else's client
/// heals them, and the screen that is waiting refetches when the doorbell
/// rings — so it needs its own answer rather than an error nobody can act on.
class KeyringOutcome {
  final bool isReady;
  final bool isWaiting;
  final ChatFailure? failure;

  const KeyringOutcome.ready()
    : isReady = true,
      isWaiting = false,
      failure = null;

  const KeyringOutcome.waiting()
    : isReady = false,
      isWaiting = true,
      failure = null;

  const KeyringOutcome.failed(ChatFailure this.failure)
    : isReady = false,
      isWaiting = false;
}
