import 'dart:convert';

/// Reshaping a `users` row into what the client models expect.
///
/// Pure, and out of the repository because two of its parts need it — the
/// server details call and the member list — and because row shaping is the
/// kind of thing that is only ever wrong in one field. A missing key here is a
/// member with no avatar or a bot that renders as a person, which is invisible
/// in a repository and obvious in a test.
class ServerUserRow {
  const ServerUserRow._();

  /// The `sub` claim of a JWT, without verifying it — the client is reading its
  /// own token to know which row is "mine", and the server re-checks anyway.
  static String? uidOf(String? jwt) {
    if (jwt == null) return null;
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      return (jsonDecode(payload) as Map<String, dynamic>)['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Flattens a `users` row into the shape the client models expect, with
  /// permissions nested.
  static Map<String, dynamic> of(Map<String, dynamic> u) => {
    'id': u['id'],
    'username': u['username'],
    'display_name': u['display_name'],
    'avatar_path': u['avatar_path'],
    'chat_public_key': u['chat_public_key'],
    'is_muted': u['is_muted'],
    'is_deafened': u['is_deafened'],
    'is_banned': u['is_banned'],
    'is_bot': u['is_bot'],
    'manifest': u['manifest'],
    'permissions': {
      'is_server_admin': u['is_server_admin'],
      'is_channel_manager': u['is_channel_manager'],
      'can_create_tokens': u['can_create_tokens'],
    },
  };

  /// Folds the caller's own permission bits into the nested `permissions` map
  /// `ServerUser` reads, so the three cached booleans and the twenty-two bits
  /// arrive as one answer rather than two the client has to reconcile.
  static Map<String, dynamic> withPermissionBits(
    Map<String, dynamic> row,
    int bits,
  ) => {
    ...row,
    'permissions': {
      ...(row['permissions'] as Map<String, dynamic>),
      'permission_bits': bits,
    },
  };
}
