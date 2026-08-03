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

  /// X25519 chat key (base64) — null until the member publishes one. Needed
  /// to start an E2E DM with them.
  final String? chatPublicKey;

  /// Object name of the avatar inside the `avatars` bucket, or null.
  final String? avatarPath;

  const ServerMember({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
    this.isMuted = false,
    this.isDeafened = false,
    this.isBanned = false,
    this.chatPublicKey,
    this.avatarPath,
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
      chatPublicKey: json['chat_public_key'] as String?,
      avatarPath: json['avatar_path'] as String?,
    );
  }

  ServerMember copyWith({
    UserPermissions? permissions,
    bool? isMuted,
    bool? isDeafened,
  }) {
    return ServerMember(
      id: id,
      username: username,
      displayName: displayName,
      permissions: permissions ?? this.permissions,
      isMuted: isMuted ?? this.isMuted,
      isDeafened: isDeafened ?? this.isDeafened,
      isBanned: isBanned,
      chatPublicKey: chatPublicKey,
      avatarPath: avatarPath,
    );
  }
}
