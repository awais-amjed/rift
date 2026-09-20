import 'package:flutter/material.dart';

import '../../../../../common/app_button.dart';
import '../../../dms/widgets/friends/friend_row_action.dart';

/// One [FriendRowAction], drawn full width with its name showing.
///
/// On a friends row these are bare circles and the name lives in a tooltip,
/// because a row has no width to spare. A dialog does, and "Block" spelled
/// out is the difference between a button somebody presses on purpose and one
/// they discover by pressing it — which for half of these is not recoverable.
class ProfileActionButton extends StatelessWidget {
  final FriendRowAction action;

  const ProfileActionButton({super.key, required this.action});

  @override
  Widget build(BuildContext context) {
    return AppButton(
      // The tooltip *is* the action's name — [FriendRowAction] keeps it
      // non-optional for exactly this reason.
      label: action.tooltip,
      variant: action.isDangerous
          ? AppButtonVariant.danger
          : AppButtonVariant.secondary,
      expanded: true,
      icon: Icon(action.icon, size: 15),
      onPressed: action.onTap,
    );
  }
}
