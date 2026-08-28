import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/custom_colors.dart';
import 'widgets/members_list.dart';
import 'widgets/members_modal_header.dart';
import '../../../theme/app_text.dart';
import '../roles/roles_dialog.dart';
import '../../../../data/classes/role.dart';

/// Members dialog — lists everyone on [server] with their permissions and
/// moderation state. Server admins manage permissions here (Discord-style:
/// invites grant nothing, promotion happens after joining); admins and
/// channel managers get mute/deafen controls.
///
/// Takes the server rather than reading the selection: it opens from the rail's
/// menu, which can be a server you are not currently looking at. Every call it
/// makes names that server, so the roster and the permission writes cannot drift
/// onto a different one.
class MembersModal extends StatefulWidget {
  final Server server;

  const MembersModal({super.key, required this.server});

  @override
  State<MembersModal> createState() => _MembersModalState();
}

class _MembersModalState extends State<MembersModal> {
  List<ServerMember>? _members;

  /// Loaded alongside the roster, because a member row shows both and a second
  /// spinner for the half that arrives later would be worse than one wait.
  Map<String, List<Role>> _memberRoles = const {};
  String? _error;
  String? _expandedId;

  /// Member id with an in-flight permission/moderation call.
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<ServerCubit>();
    final result = await cubit.listMembers(serverId: widget.server.id);
    final memberRoles = await cubit.listMemberRoles();
    if (!mounted) return;
    setState(() {
      _members = result.members;
      _memberRoles = memberRoles;
      _error = result.error;
    });
  }

  Future<void> _moderate(
    ServerMember member, {
    bool? muted,
    bool? deafened,
    bool? banned,
  }) async {
    setState(() => _busyId = member.id);
    final response = await context.read<ServerCubit>().moderateUser(
      userId: member.id,
      isMuted: muted,
      isDeafened: deafened,
      isBanned: banned,
      serverId: widget.server.id,
    );
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (response.success) {
        _members = _members!
            .map(
              (m) => m.id == member.id
                  ? m.copyWith(
                      isMuted: muted,
                      isDeafened: deafened,
                      isBanned: banned,
                    )
                  : m,
            )
            .toList();
      } else {
        _error = response.error;
      }
    });
  }

  /// The roles list, on top of this one rather than replacing it — you come
  /// here to look at a person, and the roles are what explains them.
  void _openRoles(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: const RolesDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        // Live rather than read off the passed-in snapshot, so being demoted
        // while the dialog is open takes the controls away.
        final viewer = context
            .watch<ServerCubit>()
            .state
            .serverById(widget.server.id)
            ?.user;
        final viewerPerms = viewer?.permissions;
        final viewerIsAdmin = viewerPerms?.isServerAdmin ?? false;
        final viewerIsModerator =
            viewerIsAdmin || (viewerPerms?.isChannelManager ?? false);

        return Dialog(
          // The panel surface, like every other dialog. On the canvas colour
          // it read as a hole punched through the app rather than a card
          // floating over it.
          backgroundColor: themeState.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(K.radiusDialog),
            side: BorderSide(color: themeState.borderElevated),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MembersModalHeader(
                  count: _members?.length,
                  serverName: widget.server.name,
                  themeState: themeState,
                  onOpenRoles: () => _openRoles(context),
                ),
                Divider(height: 1, color: themeState.borderPrimary),

                // ── Body ────────────────────────────────────────────
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Text(
                      _error!,
                      style: AppText.secondary.copyWith(
                        fontSize: 12,
                        color: CustomColors.error,
                      ),
                    ),
                  ),
                if (_members == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )
                else if (_members != null)
                  Flexible(
                    child: MembersList(
                      members: _members!,
                      memberRoles: _memberRoles,
                      viewerId: viewer?.id,
                      viewerIsAdmin: viewerIsAdmin,
                      viewerIsModerator: viewerIsModerator,
                      expandedId: _expandedId,
                      busyId: _busyId,
                      onTap: (member) => setState(() {
                        _expandedId = _expandedId == member.id
                            ? null
                            : member.id;
                      }),
                      onModerate: _moderate,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
