import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One tickable person in [ChannelMemberPicker].
///
/// A row rather than a `CheckboxListTile`: the whole line is the target, and
/// the tick is drawn as a filled circle so a selected row reads at a glance
/// down a list of twenty rather than needing to be read one at a time.
class MemberPickRow extends StatelessWidget {
  final ServerMember member;
  final bool checked;
  final VoidCallback? onTap;

  const MemberPickRow({
    super.key,
    required this.member,
    required this.checked,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          spacing: 10,
          children: [
            UserAvatar(
              avatarPath: member.avatarPath,
              name: member.displayName,
              size: 24,

              seed: member.id,
            ),
            Expanded(
              child: Text(
                member.displayName,
                overflow: TextOverflow.ellipsis,
                style: AppText.row.copyWith(color: themeState.textPrimary),
              ),
            ),
            Icon(
              checked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 18,
              color: checked
                  ? themeState.accentBright
                  : themeState.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
