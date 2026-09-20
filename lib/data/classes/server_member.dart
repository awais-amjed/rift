import 'bot_manifest.dart';
import 'user_permissions.dart';

/// A member of a server as returned by the `list_users` edge function —
/// profile, permissions, and moderation state for the members dialog.
class ServerMember {
  final String id;
  final String username;
  final String displayName;
  final UserPermissions permissions;
  final bool isMuted;
  final bool isDeafened;
  final bool isBanned;

  /// A program, not a person (`005_bots.sql`). Set at registration from the
  /// invite and never afterwards.
  ///
  /// It changes more than a label: a bot is listed apart from the members
  /// (BOTS.md §9) and can never be handed a channel key, so anything that
  /// reasons about "who can read this room" has to know the difference.
  final bool isBot;

  /// What this bot says it can do (`005_bots.sql`). [BotManifest.empty] for a
  /// person, and for a bot that has published nothing.
  final BotManifest manifest;

  /// X25519 chat key (base64) — null until the member publishes one. Needed
  /// to start an E2E DM with them.
  final String? chatPublicKey;

  /// Object name of the avatar inside the `avatars` bucket, or null.
  final String? avatarPath;

  /// When they joined **this** server (`users.created_at`), or null on a
  /// server too old to send the column.
  ///
  /// Only ever this server's tenure. Servers do not know about each other and
  /// the central tier is not asked, so there is no global "member since" this
  /// could be mistaken for — the profile says which server it means.
  final DateTime? joinedAt;

  const ServerMember({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
    this.isMuted = false,
    this.isDeafened = false,
    this.isBanned = false,
    this.isBot = false,
    this.manifest = BotManifest.empty,
    this.chatPublicKey,
    this.avatarPath,
    this.joinedAt,
  });

  factory ServerMember.fromJson(Map<String, dynamic> json) {
    return ServerMember(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      permissions: json['permissions'] != null
          ? UserPermissions.fromJson(
              json['permissions'] as Map<String, dynamic>,
            )
          : const UserPermissions(),
      isMuted: json['is_muted'] == true,
      isDeafened: json['is_deafened'] == true,
      isBanned: json['is_banned'] == true,
      isBot: json['is_bot'] == true,
      manifest: BotManifest.fromJson(json['manifest'] as Map<String, dynamic>?),
      chatPublicKey: json['chat_public_key'] as String?,
      avatarPath: json['avatar_path'] as String?,
      joinedAt: DateTime.tryParse(json['joined_at'] as String? ?? ''),
    );
  }

  /// The members inside a `{'users': [...]}` envelope.
  ///
  /// Every call in the member directory (`011_directory.sql`) answers in that shape —
  /// a page, a search, a batch of resolved ids — so the parse is here once
  /// rather than repeated per call. A missing or malformed envelope is an empty
  /// list, not a throw: these feed lists and typeaheads, and a search box is
  /// not where a transport problem should surface.
  static List<ServerMember> listFrom(Object? data) {
    final rows = (data is Map<String, dynamic> ? data['users'] : null) as List?;
    return [
      for (final row in rows ?? const [])
        if (row is Map<String, dynamic>) ServerMember.fromJson(row),
    ];
  }

  ServerMember copyWith({
    UserPermissions? permissions,
    bool? isMuted,
    bool? isDeafened,
    bool? isBanned,
  }) {
    return ServerMember(
      id: id,
      username: username,
      displayName: displayName,
      permissions: permissions ?? this.permissions,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isBanned: isBanned ?? this.isBanned,
      // Not a parameter: `is_bot` is pinned server-side (`005_bots.sql`) and a
      // copyWith that could change it would be the one place in the client
      // where a person turns into a program.
      isBot: isBot,
      manifest: manifest,
      chatPublicKey: chatPublicKey,
      avatarPath: avatarPath,
      joinedAt: joinedAt,
    );
  }
}
