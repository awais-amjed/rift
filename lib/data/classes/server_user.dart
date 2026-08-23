import 'user_permissions.dart';

class ServerUser {
  final String id;
  final String username;
  final String displayName;
  final UserPermissions permissions;

  /// Object name of the avatar inside the server's `avatars` bucket, or null
  /// for no avatar (render initials). Not a URL — see migration 014.
  final String? avatarPath;

  /// Whether this server has banned us.
  ///
  /// Read from our own row, which stays selectable while banned precisely so
  /// this can be answered — every other read returns empty, because
  /// `app.server_id()` is null for a banned member, and "empty" is not
  /// something a client can tell apart from "nothing here yet".
  final bool isBanned;

  const ServerUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
    this.avatarPath,
    this.isBanned = false,
  });

  ServerUser copyWith({
    String? displayName,
    String? avatarPath,
    bool? isBanned,
  }) => ServerUser(
    id: id,
    username: username,
    displayName: displayName ?? this.displayName,
    permissions: permissions,
    avatarPath: avatarPath ?? this.avatarPath,
    isBanned: isBanned ?? this.isBanned,
  );

  factory ServerUser.fromJson(Map<String, dynamic> json) {
    return ServerUser(
      id: json['id'] as String,
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      permissions: json['permissions'] != null
          ? UserPermissions.fromJson(
              json['permissions'] as Map<String, dynamic>,
            )
          : const UserPermissions(),
      avatarPath: json['avatar_path'] as String?,
      // Deliberately not persisted (see toJson): a ban read at launch has to
      // come from the server, not from what we believed last time.
      isBanned: json['is_banned'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'permissions': permissions.toJson(),
    'avatar_path': ?avatarPath,
  };
}
