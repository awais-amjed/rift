import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../../data/device_id.dart';
import '../../services/hydrated_keys.dart';

part 'token_state.dart';

/// Caches LiveKit tokens per channel so they can be reused within their
/// 1-hour TTL. Tokens are considered valid for 55 minutes to give a safety
/// margin before expiry.
///
/// **Scoped to the user, not just the channel.** The cache is keyed by
/// channel and survives a restart, so signing out and signing back in as
/// someone else used to hand the new account the old one's token — and a
/// LiveKit token is an identity, not a credential to a shared room. The
/// symptom was a voice tile labelled with the previous account's name; the
/// cause was that the connection really was theirs, on the same device, with
/// their moderation grant. Every read now has to name the user it is for.
class TokenCubit extends HydratedCubit<TokenState> {
  TokenCubit() : super(const TokenState());

  /// A fixed name, not the class's: see [HydratedKeys].
  @override
  String get storagePrefix => HydratedKeys.token;

  /// Bumped whenever the server starts minting a *different* grant — a new
  /// permission in the token, a new identity shape.
  ///
  /// A cached token carries the grant it was minted with, and nothing about a
  /// server-side change reaches a client holding one: it keeps using the old
  /// grant until the token expires, which is most of an hour of the new
  /// behaviour quietly not working. Bumping this drops every token from before
  /// the change on the first read after the app updates.
  ///
  /// 2 — `canUpdateOwnMetadata`, so a client can publish its own deafen.
  static const grantVersion = 2;

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  /// Returns a cached token for [channelId] if one exists, belongs to
  /// [supabaseUrl] *and to [userId]*, and was created within the last 55
  /// minutes. Returns `null` if no valid token is cached.
  CachedToken? getValidToken(
    String supabaseUrl,
    String channelId,
    String userId,
  ) {
    final cached = state.tokens[channelId];
    if (cached == null) return null;
    if (cached.supabaseUrl != supabaseUrl) return null;
    // Another account's token, or one from before this was recorded. Evicted
    // rather than merely refused: it will never match again, and leaving it
    // there keeps another user's identity on disk.
    if (cached.userId != userId) {
      _evict(channelId);
      return null;
    }
    // Minted with a grant this build no longer expects. Same treatment as
    // another account's: it will never match again.
    if (cached.grantVersion != grantVersion) {
      _evict(channelId);
      return null;
    }
    // Minted in an earlier run, under that run's device id. A share asks for
    // its token fresh, under this run's, so a call joined on the old one no
    // longer recognises its own stream: the sharer is shown their own screen
    // as somebody else's and hears their own sound share back.
    if (cached.deviceId != DeviceId.current) {
      _evict(channelId);
      return null;
    }
    if (!cached.isValid) {
      // Evict expired entry
      _evict(channelId);
      return null;
    }
    return cached;
  }

  /// Stores a newly fetched token for [channelId], against the user it was
  /// minted for, and the LiveKit the mint named — see [CachedToken.livekitUrl].
  void saveToken(
    String supabaseUrl,
    String channelId,
    String userId,
    String token, {
    String? livekitUrl,
  }) {
    final updated = Map<String, CachedToken>.from(state.tokens);
    updated[channelId] = CachedToken(
      grantVersion: grantVersion,
      deviceId: DeviceId.current,
      supabaseUrl: supabaseUrl,
      channelId: channelId,
      userId: userId,
      token: token,
      createdAt: DateTime.now(),
      livekitUrl: livekitUrl,
    );
    emit(state.copyWith(tokens: updated));
  }

  /// Removes the cached token for [channelId] (e.g. on auth error).
  void invalidateToken(String channelId) => _evict(channelId);

  /// Drops every cached token issued by [supabaseUrl].
  ///
  /// A LiveKit token carries the moderation grant it was minted with, and stays
  /// usable for 55 minutes — so a member muted mid-session would get their old
  /// permissions straight back by leaving and rejoining. Called when the local
  /// user's own mute/deafen state changes.
  void invalidateServerTokens(String supabaseUrl) {
    final updated = Map<String, CachedToken>.from(state.tokens)
      ..removeWhere((_, token) => token.supabaseUrl == supabaseUrl);
    if (updated.length == state.tokens.length) return;
    emit(state.copyWith(tokens: updated));
  }

  // ──────────────────────────────────────────────────────────
  // HydratedCubit persistence
  // ──────────────────────────────────────────────────────────

  @override
  TokenState? fromJson(Map<String, dynamic> json) {
    try {
      final raw = json['tokens'] as Map<String, dynamic>? ?? {};
      final tokens = raw.map(
        (key, value) =>
            MapEntry(key, CachedToken.fromJson(value as Map<String, dynamic>)),
      );
      return TokenState(tokens: tokens);
    } catch (_) {
      return const TokenState();
    }
  }

  @override
  Map<String, dynamic>? toJson(TokenState state) => {
    'tokens': state.tokens.map((key, value) => MapEntry(key, value.toJson())),
  };

  // ──────────────────────────────────────────────────────────
  // Private helpers
  // ──────────────────────────────────────────────────────────

  void _evict(String channelId) {
    if (!state.tokens.containsKey(channelId)) return;
    final updated = Map<String, CachedToken>.from(state.tokens)
      ..remove(channelId);
    emit(state.copyWith(tokens: updated));
  }
}
