import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server_member.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/quiet_danger_button.dart';
import '../../../roles/member_roles_dialog.dart';
import 'profile_section.dart';

/// What staff can do to this person, from the profile.
///
/// Shortcuts, not a second implementation: every control here calls the same
/// `moderate_user` the members dialog does, and Roles opens that dialog
/// rather than growing its own copy of the ladder. A profile is where you end
/// up when you have just read something somebody wrote and want to act on it,
/// and making that a trip through Server settings → Members → search → expand
/// is the reason nobody ever does.
///
/// Two permissions, and they are not the same reach: mute and deafen are a
/// moderator's, roles and the ban are an admin's — and the server refuses
/// both against another admin, so neither is offered there.
class ProfileModeration extends StatelessWidget {
  final ServerMember member;
  final bool isBusy;
  final bool canModerate;
  final bool isAdmin;

  final void Function({bool? muted, bool? deafened, bool? banned}) onModerate;

  const ProfileModeration({
    super.key,
    required this.member,
    required this.isBusy,
    required this.canModerate,
    required this.isAdmin,
    required this.onModerate,
  });

  /// Bans ask first; lifting one doesn't — the same asymmetry the members
  /// dialog uses, and for the same reason: only one of the two cuts somebody
  /// off mid-sentence.
  Future<void> _toggleBan(BuildContext context) async {
    if (member.isBanned) {
      onModerate(banned: false);
      return;
    }
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Ban ${member.displayName}?',
      message:
          'They lose access to this server immediately, including anything '
          'they are in the middle of. Their messages stay, and you can lift '
          'this again from the members list.',
      confirmLabel: 'Ban',
      icon: Icons.gavel_rounded,
      isDestructive: true,
    );
    if (confirmed) onModerate(banned: true);
  }

  void _openRoles(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: MemberRolesDialog(member: member),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Never against another admin: `moderate_user` refuses it, and a button
    // that comes back "cannot_moderate_admin" is worse than no button.
    final reachable = !member.permissions.isServerAdmin;
    if (!reachable || (!canModerate && !isAdmin)) {
      return const SizedBox.shrink();
    }

    return ProfileSection(
      label: 'Moderation',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          if (canModerate)
            Row(
              spacing: 6,
              children: [
                Expanded(
                  child: QuietDangerButton(
                    icon: member.isMuted ? Icons.mic : Icons.mic_off,
                    label: member.isMuted ? 'Unmute' : 'Server mute',
                    isDangerous: !member.isMuted,
                    onTap: isBusy
                        ? null
                        : () => onModerate(muted: !member.isMuted),
                  ),
                ),
                Expanded(
                  child: QuietDangerButton(
                    icon: member.isDeafened ? Icons.headset : Icons.headset_off,
                    label: member.isDeafened ? 'Undeafen' : 'Server deafen',
                    isDangerous: !member.isDeafened,
                    onTap: isBusy
                        ? null
                        : () => onModerate(deafened: !member.isDeafened),
                  ),
                ),
              ],
            ),
          if (isAdmin) ...[
            AppButton(
              label: 'Edit roles',
              variant: AppButtonVariant.secondary,
              expanded: true,
              icon: const Icon(Icons.shield_outlined, size: 15),
              onPressed: () => _openRoles(context),
            ),
            QuietDangerButton(
              icon: member.isBanned
                  ? Icons.lock_open_rounded
                  : Icons.gavel_rounded,
              label: member.isBanned ? 'Lift ban' : 'Ban from server',
              isDangerous: !member.isBanned,
              onTap: isBusy ? null : () => _toggleBan(context),
            ),
          ],
        ],
      ),
    );
  }
}
