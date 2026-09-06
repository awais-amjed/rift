part of 'invites_panel.dart';

/// The roles half of the invite dialog: which ones this member may hand out,
/// and which one the link being minted names.
///
/// Split from the dialog because it answers a different question than the rest
/// of it. Everything else here is about the *link* — how long it lasts, how
/// many times it works, whether it makes a bot. This is about what the person
/// on the other end becomes, and it is the only part that has to ask the server
/// anything before the dialog can be drawn.
mixin _InviteRolesMixin on State<InvitesPanel> {
  /// The role this link hands out, or null for a plain one.
  String? roleId;

  /// Only what the minter may actually hand out. The policy refuses the rest,
  /// and an option that always fails is worse than no option — so a member with
  /// no `MANAGE_ROLES` gets an empty list, and the picker hides itself.
  List<Role> roles = const [];

  Role? get selectedRole {
    for (final role in roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  Future<void> loadRoles() async {
    final cubit = context.read<ServerCubit>();
    final me = cubit.state.selectedServer?.user?.id;
    final all = await cubit.listRoles();
    final assignments = await cubit.listMemberRoles();
    if (!mounted) return;

    final bits = cubit.state.selectedServer?.user?.permissions.bits ?? 0;
    setState(() {
      roles = RoleLadder.assignable(
        all,
        RoleLadder.rankOf(assignments, me),
        isAdministrator: bits.has(ServerPermission.administrator),
      );
    });
  }
}
