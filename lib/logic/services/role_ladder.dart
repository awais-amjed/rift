import '../../data/classes/role.dart';

/// Where somebody stands on a server's role ladder, and what that lets them
/// hand out.
///
/// Every delegation rule is decided on position — you may
/// only touch a role strictly below your own — and on being an
/// administrator at all. So this is the
/// same two lines four different screens were each working out for themselves:
/// the roles list, one member's roles, the participant menu and the invite
/// dialog. Four copies of a rule is three chances to get it subtly wrong, and
/// the wrong ones fail by *offering* something the database then refuses.
///
/// It is not the enforcement. `roles_insert`, `roles_update` and
/// `member_roles_insert` are, and they would refuse the same thing if every
/// line here were deleted. This is what stops a screen offering it.
class RoleLadder {
  const RoleLadder._();

  /// `member_role_list` rows grouped by member, each list most senior first.
  ///
  /// The rows arrive flat — one per (member, role) — from two different calls
  /// now that the roster pages: `listMemberRoles` for a whole server, and
  /// `memberRolesFor` for the handful of rows on screen. Both want the same
  /// shape, and a second copy of the grouping is where the sort order quietly
  /// stops matching and one screen starts showing the junior role.
  static Map<String, List<Role>> byUser(List<Map<String, dynamic>> rows) {
    final byUser = <String, List<Role>>{};
    for (final row in rows) {
      byUser
          .putIfAbsent(row['user_id'] as String, () => [])
          .add(Role.fromJson({...row, 'id': row['role_id']}));
    }
    for (final roles in byUser.values) {
      roles.sort((a, b) => b.position.compareTo(a.position));
    }
    return byUser;
  }

  /// The highest position among the roles [userId] actually holds.
  ///
  /// Zero for somebody holding none — and `@everyone` does not count, because
  /// it is never assigned. Zero is the correct answer: they can touch nothing,
  /// since nothing sits strictly below the ground.
  static int rankOf(Map<String, List<Role>> assignments, String? userId) {
    if (userId == null) return 0;
    var rank = 0;
    for (final role in assignments[userId] ?? const <Role>[]) {
      if (role.position > rank) rank = role.position;
    }
    return rank;
  }

  /// Everything an administrator at [rank] may **edit or reorder**, most
  /// senior first. Empty for anybody else: the editor is an
  /// administrator's, whatever bits somebody holds.
  ///
  /// The baseline is excluded. It is not a rung on the ladder — it is what
  /// holding nothing already gets you — so it can be edited but never
  /// assigned or reordered.
  static List<Role> below(
    List<Role> roles,
    int rank, {
    required bool isAdministrator,
  }) => [
    if (isAdministrator)
      for (final role in roles)
        if (!role.isEveryone && role.position < rank) role,
  ];

  /// Everything they may **hand out**, which is not the same list.
  ///
  /// Editing is strictly-below; assigning is at-or-below, so the only admin
  /// on a server can make a second one. Both are an administrator's alone,
  /// and the owner role is on neither list — it outranks
  /// everybody and moves only by transfer.
  static List<Role> assignable(
    List<Role> roles, {
    required bool isAdministrator,
  }) => [
    if (isAdministrator)
      for (final role in roles)
        if (!role.isEveryone && !role.isOwner) role,
  ];
}
