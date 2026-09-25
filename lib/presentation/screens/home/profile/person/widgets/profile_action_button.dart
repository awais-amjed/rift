import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/quiet_danger_button.dart';
import '../../../dms/widgets/friends/friend_row_action.dart';

/// One [FriendRowAction], drawn full width with its name showing.
///
/// On a friends row these are bare circles and the name lives in a tooltip,
/// because a row has no width to spare. A dialog does, and "Block" spelled
/// out is the difference between a button somebody presses on purpose and one
/// they discover by pressing it — which for half of these is not recoverable.
///
/// The destructive ones are [QuietDangerButton]s rather than solid danger
/// fills: a friend's profile offers two of them at once, stacked under the
/// Message button, and two walls of the error colour make the page look like
/// it is about ending the friendship rather than about the person.
class ProfileActionButton extends StatelessWidget {
  final FriendRowAction action;

  const ProfileActionButton({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    // The tooltip *is* the action's name — [FriendRowAction] keeps it
    // non-optional for exactly this reason.
    if (action.isDangerous) {
      return QuietDangerButton(
        icon: action.icon,
        label: action.tooltip,
        onTap: action.onTap,
      );
    }
    return AppButton(
      label: action.tooltip,
      variant: AppButtonVariant.secondary,
      expanded: true,
      icon: Icon(action.icon, size: K.iconRow),
      onPressed: action.onTap,
    );
  }
}
