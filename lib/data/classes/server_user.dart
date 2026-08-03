import 'user_permissions.dart';

class ServerUser {
  final String id;
  final String username;
  final String displayName;
  final UserPermissions permissions;

  /// Object name of the avatar inside the server's `avatars` bucket, or null
  /// for no avatar (render initials). Not a URL — see migration 014.
  final String? avatarPath;

  const ServerUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
    this.avatarPath,
  });

  ServerUser copyWith({String? displayName, String? avatarPath}) => ServerUser(
    id: id,
    username: username,
    displayName: displayName ?? this.displayName,
    permissions: permissions,
    avatarPath: avatarPath ?? this.avatarPath,
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
