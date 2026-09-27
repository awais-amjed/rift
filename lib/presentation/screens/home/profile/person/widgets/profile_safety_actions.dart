import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server_member.dart';
import '../../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/quiet_danger_button.dart';
import '../../../reports/show_report_dialog.dart';

/// Block and Report, for anybody looking at somebody else's profile.
///
/// Not moderation — every member has these, and neither needs a permission.
/// Blocking is between two people and nobody else is told, not even the
/// person blocked; reporting goes to the server's moderators.
class ProfileSafetyActions extends StatelessWidget {
  final ServerMember member;

  const ProfileSafetyActions({super.key, required this.member});

  Future<void> _toggleBlock(BuildContext context, bool blocked) async {
    final cubit = context.read<DmCubit>();
    if (!blocked) {
      final confirmed = await showConfirmDialog(
        context: context,
        title: 'Block ${member.displayName}?',
        message:
            'They can\'t message or call you on this server, and any request '
            'from them goes away. They aren\'t told.',
        confirmLabel: 'Block',
        icon: Icons.block_rounded,
        isDestructive: true,
      );
      if (!confirmed) return;
    }
    final response = await cubit.setBlocked(member.id, blocked: !blocked);
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'Could not do that.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = context.select<DmCubit, bool>(
      (c) => c.state.blockedIds.contains(member.id),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        spacing: 6,
        children: [
          Expanded(
            child: QuietDangerButton(
              icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
              label: blocked ? 'Unblock' : 'Block',
              isDangerous: !blocked,
              onTap: () => unawaited(_toggleBlock(context, blocked)),
            ),
          ),
          Expanded(
            child: QuietDangerButton(
              icon: Icons.flag_outlined,
              label: 'Report',
              isDangerous: true,
              onTap: () => unawaited(
                showReportMemberDialog(
                  context,
                  userId: member.id,
                  displayName: member.displayName,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
