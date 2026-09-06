import '../../data/classes/role.dart';

/// Where somebody stands on a server's role ladder, and what that lets them
/// hand out.
///
/// Every delegation rule in migration 018 is decided on position and nothing
/// else — you may only touch a role strictly below your own — so this is the
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

  /// The roles worth showing beside somebody's name.
  ///
  /// Everything except the default one. Every member is given that on
  /// registration, so a chip for it appeared on every row saying what was true
  /// of everybody — and a badge that never varies is not a badge, it is
  /// furniture that the roles somebody should notice have to compete with.
  ///
  /// Only the *chip* is dropped. The roles editor and the per-member menu still
  /// list it, because it is a real assignment that can be taken away, and a
  /// role you cannot see is a role you cannot remove.
  static List<Role> badges(List<Role> roles) => [
    for (final role in roles)
      if (!role.isDefault) role,
  ];

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

  /// Everything somebody at [rank] may **edit or reorder**, most senior first.
  ///
  /// The baseline is excluded. It is not a rung on the ladder — it is what
  /// holding nothing already gets you — so it can be edited by whoever holds
  /// `MANAGE_ROLES` but never assigned or reordered.
  static List<Role> below(List<Role> roles, int rank) => [
    for (final role in roles)
      if (!role.isEveryone && role.position < rank) role,
  ];

  /// Everything they may **hand out**, which is not the same list.
  ///
  /// Editing is strictly-below for everybody: nobody rewrites the role they are
  /// standing on. Assigning is strictly-below too, *except* for an
  /// administrator — otherwise the only admin on a server could never make a
  /// second one, which `set_user_permissions` allowed from 003 until 025 and
  /// `member_roles_insert` has allowed since 018.
  ///
  /// The asymmetry is easy to get wrong in one screen and not another, which
  /// is the whole reason it is written once. Taking a role *off* is governed by
  /// the same exemption, minus your own (026).
  ///
  /// The owner role is on neither list. It outranks everybody, so the rank
  /// rule alone keeps it out of [below]; the administrator exemption here
  /// would let it through, and the database (013) refuses it — so it is
  /// named, rather than left to be offered and then refused.
  static List<Role> assignable(
    List<Role> roles,
    int rank, {
    required bool isAdministrator,
  }) => [
    for (final role in roles)
      if (!role.isEveryone &&
          !role.isOwner &&
          (isAdministrator || role.position < rank))
        role,
  ];
}
