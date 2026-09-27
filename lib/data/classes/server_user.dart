import '../enums/dm_policy.dart';
import 'user_permissions.dart';

/// Our own member row on one server: who we appear as there, and what we may do.
class ServerUser {
  final String id;
  final String username;
  final String displayName;
  final UserPermissions permissions;

  /// Object name of the avatar inside the server's `avatars` bucket, or null
  /// for no avatar (render initials). Not a URL: the bucket is private.
  final String? avatarPath;

  /// Whether this server has banned us.
  ///
  /// Read from our own row, which stays selectable while banned precisely so
  /// this can be answered — every other read returns empty, because
  /// `app.server_id()` is null for a banned member, and "empty" is not
  /// something a client can tell apart from "nothing here yet".
  final bool isBanned;

  /// Until when we cannot post, DM or react here, or null. From the server
  /// on every refresh and never persisted, like [isBanned].
  final DateTime? timedOutUntil;

  /// Who may start a DM with us on this server.
  final DmPolicy dmPolicy;

  const ServerUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.permissions,
    this.avatarPath,
    this.isBanned = false,
    this.timedOutUntil,
    this.dmPolicy = DmPolicy.everyone,
  });

  /// Timed out right now.
  bool get isTimedOut =>
      timedOutUntil != null && timedOutUntil!.isAfter(DateTime.now());

  ServerUser copyWith({
    String? displayName,
    String? avatarPath,
    bool? isBanned,
    DmPolicy? dmPolicy,
  }) => ServerUser(
    id: id,
    username: username,
    displayName: displayName ?? this.displayName,
    permissions: permissions,
    avatarPath: avatarPath ?? this.avatarPath,
    isBanned: isBanned ?? this.isBanned,
    timedOutUntil: timedOutUntil,
    dmPolicy: dmPolicy ?? this.dmPolicy,
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
      timedOutUntil: DateTime.tryParse(
        json['timed_out_until'] as String? ?? '',
      )?.toLocal(),
      dmPolicy: DmPolicy.fromString(json['dm_policy'] as String?),
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
