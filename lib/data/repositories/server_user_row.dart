/// Reshaping a `users` row into what the client models expect.
///
/// Pure, and out of the repository because row shaping is the kind of thing
/// that is only ever wrong in one field. A missing key here is a member with
/// no avatar or a bot that renders as a person, which is invisible in a
/// repository and obvious in a test.
///
/// It used to serve the server-details call too, along with a `uidOf` that
/// read the caller's own JWT and a `stampManagedChannels` that went back to
/// the database for the manage seat. `get_server_details()`
/// builds that row in SQL now, so the member list is the only caller left.
class ServerUserRow {
  const ServerUserRow._();

  /// Flattens a `users` row into the shape the client models expect, with
  /// permissions nested.
  static Map<String, dynamic> of(Map<String, dynamic> u) => {
    'id': u['id'],
    'username': u['username'],
    'display_name': u['display_name'],
    'joined_at': u['joined_at'],
    'avatar_path': u['avatar_path'],
    'chat_public_key': u['chat_public_key'],
    'is_muted': u['is_muted'],
    'is_deafened': u['is_deafened'],
    'is_banned': u['is_banned'],
    'is_bot': u['is_bot'],
    'manifest': u['manifest'],
    'dm_policy': u['dm_policy'],
    'timed_out_until': u['timed_out_until'],
    'permissions': {
      'is_server_admin': u['is_server_admin'],
      'is_channel_manager': u['is_channel_manager'],
      'can_create_tokens': u['can_create_tokens'],
      'is_owner': u['is_owner'],
    },
  };
}
