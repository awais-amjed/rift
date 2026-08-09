import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../common/server_role.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// The submenu behind "Roles" — one row per role, ticked when held.
///
/// The ticks come from [ServerMembersCubit], which is live, so a grant made
/// from the Members dialog (or by another admin) shows here without reopening
/// the menu. Rows deliberately don't dismiss: granting two roles in a row is
/// the common case, the same reason the mute toggle leaves the menu up.
class ParticipantRolesMenu extends StatefulWidget {
  final String userId;

  const ParticipantRolesMenu({super.key, required this.userId});

  @override
  State<ParticipantRolesMenu> createState() => _ParticipantRolesMenuState();
}

class _ParticipantRolesMenuState extends State<ParticipantRolesMenu> {
  /// Which role is mid-flight — one at a time, since the three share a row in
  /// the database and overlapping writes would race on the read-modify-write.
  ServerRole? _pending;
  String? _error;

  Future<void> _toggle(ServerRole role, bool next) async {
    if (_pending != null) return;
    setState(() {
      _pending = role;
      _error = null;
    });

    final serverCubit = context.read<ServerCubit>();
    final members = context.read<ServerMembersCubit>();

    // `set_user_permissions` takes the three as separate nullable booleans,
    // where null means "leave alone".
    final response = await serverCubit.setUserPermissions(
      userId: widget.userId,
      isServerAdmin: role == ServerRole.admin ? next : null,
      isChannelManager: role == ServerRole.channelManager ? next : null,
      canCreateTokens: role == ServerRole.invites ? next : null,
    );

    // The `users` write reaches us over Realtime anyway, but that round trip is
    // long enough to leave a stale tick under the pointer that just moved it.
    if (response.success) await members.refresh();
    if (!mounted) return;
    setState(() {
      _pending = null;
      _error = response.success
          ? null
          : (response.error ?? 'Could not change that role');
    });
  }

  @override
  Widget build(BuildContext context) {
    final member = context
        .watch<ServerMembersCubit>()
        .state
        .byId[widget.userId];

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        if (member == null) {
          return ContextMenuPanel(
            heading: 'Roles',
            children: [_note('Member list still loading.', themeState)],
          );
        }

        return ContextMenuPanel(
          heading: 'Roles',
          children: [
            for (final role in ServerRole.values)
              ContextMenuItem(
                icon: role.icon,
                label: role.label,
                onTap: () => _toggle(role, !role.isHeldBy(member.permissions)),
                trailing: _trailing(
                  role: role,
                  isHeld: role.isHeldBy(member.permissions),
                  themeState: themeState,
                ),
              ),
            if (_error != null)
              _note(_error!, themeState, color: CustomColors.error),
          ],
        );
      },
    );
  }

  /// Fixed-size, so the labels stay on one column whether a role is held, in
  /// flight, or neither.
  Widget _trailing({
    required ServerRole role,
    required bool isHeld,
    required ThemeState themeState,
  }) {
    if (_pending == role) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return SizedBox(
      width: 16,
      height: 16,
      child: isHeld
          ? Icon(Icons.check_rounded, size: 16, color: themeState.accentBright)
          : null,
    );
  }

  Widget _note(String text, ThemeState themeState, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Text(
        text,
        style: AppText.label.copyWith(
          fontWeight: FontWeight.w400,
          color: color ?? themeState.textQuaternary,
        ),
      ),
    );
  }
}
