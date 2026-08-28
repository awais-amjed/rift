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
  static List<Role> assignable(
    List<Role> roles,
    int rank, {
    required bool isAdministrator,
  }) => [
    for (final role in roles)
      if (!role.isEveryone && (isAdministrator || role.position < rank)) role,
  ];
}
