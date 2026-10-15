import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../common/label_pill.dart';
import '../../../../../../../../common/member_avatar.dart';
import '../../../../../../../../theme/app_text.dart';
import '../../../../../../../../theme/theme_context.dart';

/// The top of a member card: their face, which opens their profile, their
/// name with a Bot tag for a bot, and under it either what they are sharing
/// or their handle.
class MemberCardHeader extends StatelessWidget {
  final String userId;
  final String name;
  final bool sharing;
  final bool isMe;

  /// Opens their profile. The card closes first, so the dialog is not drawn
  /// under it.
  final VoidCallback onProfile;

  const MemberCardHeader({
    super.key,
    required this.userId,
    required this.name,
    required this.sharing,
    required this.isMe,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final member = context
        .select<ServerMembersCubit, ({String? handle, bool bot})>((cubit) {
          final row = cubit.state.byId[userId];
          return (handle: row?.username, bot: row?.isBot ?? false);
        });
    final handle = member.handle;
    return Row(
      spacing: 10,
      children: [
        Tooltip(
          message: 'View profile',
          waitDuration: const Duration(milliseconds: 400),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onProfile,
              child: MemberAvatar(userId: userId, name: name, size: 36),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Row(
                spacing: 6,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.strong.copyWith(color: theme.textPrimary),
                    ),
                  ),
                  if (member.bot) const LabelPill(label: 'Bot'),
                ],
              ),
              if (sharing)
                Row(
                  spacing: 4,
                  children: [
                    // The same screen the roster row shows.
                    Icon(
                      Icons.monitor_outlined,
                      size: 14,
                      color: theme.accentBright,
                    ),
                    Flexible(
                      child: Text(
                        isMe ? 'Sharing your screen' : 'Sharing their screen',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.secondary.copyWith(
                          color: theme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                )
              else if (handle != null && handle.isNotEmpty)
                Text(
                  '@$handle',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.secondary.copyWith(color: theme.textTertiary),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
