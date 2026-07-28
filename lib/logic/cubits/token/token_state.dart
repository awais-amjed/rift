part of 'token_cubit.dart';

/// A single cached LiveKit token for a channel.
class CachedToken {
  final String supabaseUrl;
  final String channelId;
  final String token;
  final DateTime createdAt;

  const CachedToken({
    required this.supabaseUrl,
    required this.channelId,
    required this.token,
    required this.createdAt,
  });

  /// Tokens have a 1-hour TTL; we consider them valid for 55 minutes.
  bool get isValid => DateTime.now().difference(createdAt).inMinutes < 55;

  Map<String, dynamic> toJson() => {
    'supabaseUrl': supabaseUrl,
    'channelId': channelId,
    'token': token,
    'createdAt': createdAt.toIso8601String(),
  };

  factory CachedToken.fromJson(Map<String, dynamic> json) => CachedToken(
    supabaseUrl: json['supabaseUrl'] as String,
    channelId: json['channelId'] as String,
    token: json['token'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class TokenState {
  /// Map of channelId → cached token.
  final Map<String, CachedToken> tokens;

  const TokenState({this.tokens = const {}});

  TokenState copyWith({Map<String, CachedToken>? tokens}) =>
      TokenState(tokens: tokens ?? this.tokens);
}
