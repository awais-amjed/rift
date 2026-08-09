import 'package:hydrated_bloc/hydrated_bloc.dart';

part 'token_state.dart';

/// Caches LiveKit tokens per channel so they can be reused within their
/// 1-hour TTL. Tokens are considered valid for 55 minutes to give a safety
/// margin before expiry.
class TokenCubit extends HydratedCubit<TokenState> {
  TokenCubit() : super(const TokenState());

  // ──────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────

  /// Returns a cached token for [channelId] if one exists, belongs to
  /// [supabaseUrl], and was created within the last 55 minutes.
  /// Returns `null` if no valid token is cached.
  CachedToken? getValidToken(String supabaseUrl, String channelId) {
    final cached = state.tokens[channelId];
    if (cached == null) return null;
    if (cached.supabaseUrl != supabaseUrl) return null;
    if (!cached.isValid) {
      // Evict expired entry
      _evict(channelId);
      return null;
    }
    return cached;
  }

  /// Stores a newly fetched token for [channelId].
  void saveToken(String supabaseUrl, String channelId, String token) {
    final updated = Map<String, CachedToken>.from(state.tokens);
    updated[channelId] = CachedToken(
      supabaseUrl: supabaseUrl,
      channelId: channelId,
      token: token,
      createdAt: DateTime.now(),
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
