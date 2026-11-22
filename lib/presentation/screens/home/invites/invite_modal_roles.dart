part of 'invite_modal.dart';

/// The roles half of the invite dialog: which ones this member may hand out,
/// and which one the link being minted names.
///
/// Split from the dialog because it answers a different question than the rest
/// of it. Everything else here is about the *link* — how long it lasts, how
/// many times it works, whether it makes a bot. This is about what the person
/// on the other end becomes, and it is the only part that has to ask the server
/// anything before the dialog can be drawn.
mixin _InviteRolesMixin on State<InviteModal> {
  /// The role this link hands out, or null for a plain one.
  String? roleId;

  /// Only what the minter may actually hand out. The policy refuses the rest,
  /// and an option that always fails is worse than no option — so anybody but
  /// an administrator gets an empty list, and the picker hides itself.
  List<Role> roles = const [];

  Role? get selectedRole {
    for (final role in roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  Future<void> loadRoles() async {
    final cubit = context.read<ServerCubit>();
    // The server the invite is for, which the rail's menu can open on a
    // server the person is not looking at.
    final serverId = widget.server.id;
    final myId = cubit.state.meOn(serverId)?.id;
    final api = RolesApi(context.read<SessionRepository>().on(serverId));
    final (all, mine) = await (
      api.listRoles(),
      // The minter's own, since a link hands out only a role up to their
      // rank (`invites_insert` asks `app.may_assign_role`).
      myId == null ? Future.value(null) : api.memberRolesFor([myId]),
    ).wait;
    if (!mounted) return;

    final bits = cubit.state.permissionsOn(serverId)?.bits ?? 0;
    setState(() {
      roles = RoleLadder.assignable(
        all,
        isAdministrator: bits.has(ServerPermission.administrator),
        rank: RoleLadder.rankOf(mine ?? const {}, myId),
      );
    });
  }
}
