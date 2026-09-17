part of 'token_cubit.dart';

/// A single cached LiveKit token for a channel.
///
/// Carries the user it was minted for. A LiveKit token *is* an identity —
/// its `sub` is `<userId>~<deviceId>` and its `name` is the display name
/// baked in at mint time — so handing one to a different account does not
/// mislabel a tile, it signs that account into the room as someone else,
/// with whatever moderation grant the token was issued with.
class CachedToken {
  final String supabaseUrl;
  final String channelId;

  /// Null for entries persisted before this field existed. Those can never
  /// be shown to belong to anyone, so they are treated as not matching and
  /// dropped on the next read.
  final String? userId;

  final String token;
  final DateTime createdAt;

  /// Which shape of grant this token was minted with — see
  /// [TokenCubit.grantVersion]. Null for entries persisted before the field
  /// existed, which are therefore from an older one.
  final int? grantVersion;

  const CachedToken({
    required this.supabaseUrl,
    required this.channelId,
    required this.userId,
    required this.token,
    required this.createdAt,
    this.grantVersion,
  });

  /// Tokens have a 1-hour TTL; we consider them valid for 55 minutes.
  bool get isValid => DateTime.now().difference(createdAt).inMinutes < 55;

  Map<String, dynamic> toJson() => {
    'supabaseUrl': supabaseUrl,
    'channelId': channelId,
    'userId': userId,
    'token': token,
    'createdAt': createdAt.toIso8601String(),
    'grantVersion': grantVersion,
  };

  factory CachedToken.fromJson(Map<String, dynamic> json) => CachedToken(
    supabaseUrl: json['supabaseUrl'] as String,
    channelId: json['channelId'] as String,
    userId: json['userId'] as String?,
    token: json['token'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    grantVersion: json['grantVersion'] as int?,
  );
}

class TokenState {
  /// Map of channelId → cached token.
  final Map<String, CachedToken> tokens;

  const TokenState({this.tokens = const {}});

  TokenState copyWith({Map<String, CachedToken>? tokens}) =>
      TokenState(tokens: tokens ?? this.tokens);
}
