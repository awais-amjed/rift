import 'user_permissions.dart';

class ServerUser {
  final String id;
  final String username;
  final String displayName;
  final UserPermissions permissions;

  const ServerUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
  });

  factory ServerUser.fromJson(Map<String, dynamic> json) {
    return ServerUser(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      displayName:
          json['display_name'] as String? ??
          json['displayName'] as String? ??
          '',
      permissions: json['permissions'] != null
          ? UserPermissions.fromJson(
              json['permissions'] as Map<String, dynamic>,
            )
          : const UserPermissions(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'permissions': permissions.toJson(),
  };
}
