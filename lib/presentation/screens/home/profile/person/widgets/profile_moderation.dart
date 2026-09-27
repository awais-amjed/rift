import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/services/time_out_label.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/quiet_danger_button.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../reports/time_out_picker.dart';
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
/// Several permissions, and they are not the same reach: mute and deafen are
/// a moderator's, a time-out is `MUTE_MEMBERS`, the ban is `BAN_MEMBERS`, and
/// roles are an admin's — and the server refuses all of them against another
/// admin, so none is offered there.
class ProfileModeration extends StatelessWidget {
  final ServerMember member;
  final bool isBusy;
  final bool canModerate;
  final bool isAdmin;
  final bool canTimeOut;
  final bool canBan;

  final void Function({bool? muted, bool? deafened, bool? banned}) onModerate;

  /// Time them out for this long; [Duration.zero] lifts it.
  final void Function(Duration duration) onTimeOut;

  const ProfileModeration({
    super.key,
    required this.member,
    required this.isBusy,
    required this.canModerate,
    required this.isAdmin,
    required this.canTimeOut,
    required this.canBan,
    required this.onModerate,
    required this.onTimeOut,
  });

  Future<void> _toggleTimeOut(BuildContext context) async {
    if (member.isTimedOut) {
      onTimeOut(Duration.zero);
      return;
    }
    final length = await showTimeOutPicker(context, member.displayName);
    if (length != null) onTimeOut(length.duration);
  }

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
    if (!reachable || (!canModerate && !isAdmin && !canTimeOut && !canBan)) {
      return const SizedBox.shrink();
    }
    final until = member.timedOutUntil;

    return ProfileSection(
      label: 'Moderation',
      // The one block in the dialog that acts on the person instead of
      // describing them.
      ruled: true,
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
          // Two to a row, matching the pair above: four full-width bars down
          // a profile's whole width read as a stack of consequences, and the
          // ban is the only one of them that is.
          if (canTimeOut || canBan)
            Row(
              spacing: 6,
              children: [
                if (canTimeOut)
                  Expanded(
                    child: QuietDangerButton(
                      icon: Icons.timer_outlined,
                      label: member.isTimedOut ? 'End time-out' : 'Time out',
                      isDangerous: !member.isTimedOut,
                      onTap: isBusy
                          ? null
                          : () => unawaited(_toggleTimeOut(context)),
                    ),
                  ),
                if (canBan)
                  Expanded(
                    child: QuietDangerButton(
                      icon: member.isBanned
                          ? Icons.lock_open_rounded
                          : Icons.gavel_rounded,
                      label: member.isBanned ? 'Lift ban' : 'Ban from server',
                      isDangerous: !member.isBanned,
                      onTap: isBusy ? null : () => _toggleBan(context),
                    ),
                  ),
              ],
            ),
          if (member.isTimedOut && until != null)
            Text(
              'Timed out until ${timeOutEndLabel(until)}.',
              style: AppText.meta.copyWith(color: context.theme.textTertiary),
            ),
          if (isAdmin)
            AppButton(
              label: 'Edit roles',
              variant: AppButtonVariant.secondary,
              expanded: true,
              icon: const Icon(Icons.shield_outlined, size: K.iconRow),
              onPressed: () => _openRoles(context),
            ),
        ],
      ),
    );
  }
}
