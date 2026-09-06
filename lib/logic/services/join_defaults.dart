import '../../data/classes/server.dart';

/// What the join form starts with, so nobody types the same two names on
/// every server.
///
/// The username is the central handle, when there is one: it is the name the
/// person chose for themselves once, and a server they are joining is a
/// place that name should follow them to. Without a central account there is
/// nothing to follow, and the field stays empty rather than guessing from
/// another server — a per-server username was chosen for that server.
///
/// The display name follows the most recent server instead. Central has no
/// display name, and the way somebody has been showing up everywhere else is
/// the best answer to how they want to show up here. Both are only defaults:
/// the fields stay editable.
class JoinDefaults {
  const JoinDefaults._();

  static ({String username, String displayName}) of({
    required String? centralHandle,
    required List<Server> servers,
  }) {
    final latest = servers.isEmpty ? null : servers.last.user;
    return (
      username: centralHandle ?? '',
      displayName: latest?.displayName ?? '',
    );
  }
}
