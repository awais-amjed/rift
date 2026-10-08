import 'dart:async';
import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../../data/apis/voice_bots_api.dart';
import '../../data/classes/server.dart';
import '../../data/enums/error_code.dart';
import '../../data/repositories/server_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../cubits/server/server_cubit.dart';
import '../cubits/vault/vault_cubit.dart';
import '../helper_methods.dart';
import 'channel_key_chain.dart';
import 'chat_failure.dart';
import 'keyring_outcome.dart';
import 'voice_keys.dart';

part 'channel_keyring_sealing.dart';

/// Over the helper budget and one job: a device's channel keys. Sealing for
/// others is already its own part.
///
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
class ChannelKeyring with _KeyringSealingMixin {
  @override
  final ServerCubit _serverCubit;
  @override
  final VoiceBotsApi _voiceBots;
  final VaultCubit _vaultCubit;
  @override
  final CryptoRepository _crypto;

  /// Called after this client seals the current key to members who lacked it,
  /// so their waiting screens refetch. Optional: a caller that has no doorbell
  /// to ring simply heals quietly.
  @override
  final void Function()? onHealed;

  ChannelKeyring({
    required ServerCubit serverCubit,
    required SessionRepository session,
    required VaultCubit vaultCubit,
    required CryptoRepository crypto,
    this.onHealed,
  }) : _serverCubit = serverCubit,
       _voiceBots = VoiceBotsApi(session: session),
       _vaultCubit = vaultCubit,
       _crypto = crypto;

  /// Unwrapped keys for the channel this ring was last loaded for, by version.
  @override
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
    // granted channel access.
    //
    // Found the hard way. A guard keyed by server id survived the reset, so
    // every publish was silently skipped, `chat_public_key` stayed null, and
    // the member sat on "another member needs to come online" while one was.
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
    return data?[publishedChatKeyIsNew] == true;
  }

  /// Pick up key versions sealed to this member since the channel was opened,
  /// and answer whether there were any.
  ///
  /// Before rotation existed, a channel's current version could not change
  /// while you sat in it, so a client that already held a key had no reason to
  /// look again. A rotation breaks that: another member mints the next version
  /// and, until this client notices, it keeps sealing with a key the rest of
  /// the channel has moved off and cannot read what they send back.
  ///
  /// Older versions arrive this way too. A member who joined after a rotation
  /// is sealed the current key first and the top of each older stretch of
  /// linked versions as other members' sweeps get to them; each one, and
  /// everything its links open, unlocks rows that were locked.
  ///
  /// Deliberately additive, unlike [loadOrBootstrap], which clears the ring
  /// before refilling it. That is right when opening a channel and wrong here:
  /// this runs on a doorbell, against a client that is working, and a momentary
  /// network failure must not cost it the keys it already holds.
  ///
  /// [serverId] names the server for a reader who is not looking at it — a
  /// reviewer opening reports on another server's page. Null is the selected
  /// one, which is every other caller.
  Future<bool> absorbNewVersions(String channelId, {String? serverId}) async {
    final server = serverId == null
        ? _serverCubit.state.selectedServer
        : _serverCubit.state.serverById(serverId);
    if (server == null) return false;
    final identity = await chatIdentity(server);
    if (identity == null) return false;

    final response = await _serverCubit.getChannelKey(
      channelId,
      serverId: server.id,
    );
    if (!response.success) return false;

    final data = response.data as Map<String, dynamic>;
    final version = data['current_version'] as int;

    final before = keys.length;
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
    await _followLinks(channelId, data);
    final gained = keys.length > before;

    // Only move up once the new key is actually in hand. Announcing a version
    // we cannot seal with would break sending outright, where staying put
    // leaves the client working until the rotation reaches it.
    if (version > currentVersion && keys.containsKey(version)) {
      currentVersion = version;
    }
    return gained;
  }

  /// Open older versions from [data]'s links, keeping what [keys] holds, and
  /// answer which of [own] they confirmed (see [ChannelKeyChain.follow]).
  Future<Set<int>> _followLinks(
    String channelId,
    Map<String, dynamic> data, {
    Set<int> own = const {},
  }) => ChannelKeyChain.follow(
    crypto: _crypto,
    channelId: channelId,
    keys: keys,
    links: ((data['links'] as List?) ?? const []).cast<Map<String, dynamic>>(),
    own: own,
  );

  /// Seal a media key to any bot in [channelId] that is short of one.
  ///
  /// The same `bots_missing` [loadOrBootstrap] acts on, asked again without
  /// reloading the keyring. A summon is why: it is the one thing that puts a
  /// bot on that list *while the call is already running*, and everything else
  /// that seals runs when somebody joins. Without this a bot summoned into a
  /// call full of people waits for one of them to rejoin before it can speak —
  /// which is to say, in the common case, forever.
  ///
  /// Fire-and-forget like the sealing it delegates to: a bot short of a key is
  /// a bot nobody can hear yet, not a reason to fail the caller.
  Future<void> sealMissingBotKeys(String channelId) async {
    final version = currentVersion;
    if (!keys.containsKey(version)) return;

    final response = await _serverCubit.getChannelKey(channelId);
    if (!response.success) return;

    final data = response.data as Map<String, dynamic>;
    final bots = (data['bots_missing'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    if (bots.isEmpty) return;
    await sealBotKeys(channelId, version, bots);
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

      // Unwrap every version sealed to us, then open the rest of the
      // scrollback from the links below them.
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
      final covered = await _followLinks(
        channelId,
        data,
        own: keys.keys.toSet(),
      );
      currentVersion = version;
      // Rows the chain reaches, checked against what they hold, are rows this
      // member no longer needs. Never the current one: a rotation is sealed
      // from it, and nothing newer links down to it yet.
      final droppable = covered.where((v) => v < version).toList();
      if (droppable.isNotEmpty) {
        unawaited(_serverCubit.pruneChannelKeys(channelId, droppable));
      }

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
      mint: true,
    );

    if (response.success) {
      keys[1] = channelKey;
      currentVersion = 1;
      // Seal the bots now, because the answer that sent us down this path
      // could not have listed them. The server only computes `bots_missing`
      // once a version exists, so the call that said "no key yet" carried an
      // empty list by construction — and `loadOrBootstrap` returns here rather
      // than falling through to the branch that seals.
      //
      // The member who *creates* a voice channel is usually the first one in
      // it, so without this a bot summoned to a new channel stayed silent
      // until somebody left and rejoined. Fire-and-forget, like every other
      // seal: a bot short of a key is a bot nobody can hear yet, not a reason
      // to fail opening the channel.
      unawaited(sealMissingBotKeys(channelId));
      return const KeyringOutcome.ready();
    }
    if (response.errorCode == ErrorCode.keyringConflict) {
      // Not a failure: the caller refetches the winner's ring.
      return const KeyringOutcome.waiting();
    }
    return KeyringOutcome.failed(ChatFailure.fromResponse(response));
  }
}
