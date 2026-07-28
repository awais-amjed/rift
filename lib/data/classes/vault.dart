import 'dart:convert';

/// Represents the decrypted vault containing the user's master identity
/// and a list of servers they've joined.
class Vault {
  final String masterSeed; // base64-encoded 256-bit seed
  final List<JoinedServer> joinedServers;

  const Vault({required this.masterSeed, this.joinedServers = const []});

  Map<String, dynamic> toJson() => {
    'master_seed': masterSeed,
    'joined_servers': joinedServers.map((s) => s.toJson()).toList(),
  };

  factory Vault.fromJson(Map<String, dynamic> json) => Vault(
    masterSeed: json['master_seed'] as String,
    joinedServers:
        (json['joined_servers'] as List<dynamic>?)
            ?.map((e) => JoinedServer.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
  );

  String toJsonString() => jsonEncode(toJson());

  factory Vault.fromJsonString(String jsonString) =>
      Vault.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);

  Vault copyWith({String? masterSeed, List<JoinedServer>? joinedServers}) {
    return Vault(
      masterSeed: masterSeed ?? this.masterSeed,
      joinedServers: joinedServers ?? this.joinedServers,
    );
  }
}

/// A server the user has joined, stored inside the vault.
class JoinedServer {
  final String url;
  final String version;
  final DateTime joinedAt;

  const JoinedServer({
    required this.url,
    required this.version,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'version': version,
    'joined_at': joinedAt.toIso8601String(),
  };

  factory JoinedServer.fromJson(Map<String, dynamic> json) => JoinedServer(
    url: json['url'] as String,
    version: json['version'] as String,
    joinedAt: DateTime.parse(json['joined_at'] as String),
  );
}
