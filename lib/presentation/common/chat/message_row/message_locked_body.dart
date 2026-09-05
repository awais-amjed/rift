import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';

/// Stands in for a message sealed under a key this device does not hold.
///
/// It exists so a channel looks like what it is. Before this, an unopenable
/// message was dropped on the floor, so a member nobody had wrapped for yet
/// opened a busy channel and found an empty room — or, once webhooks arrived, a
/// room that appeared to contain nothing but build alerts.
///
/// Deliberately quiet: the author and the time are real and come from columns
/// the server already keeps in the clear, and the row says only that there is
/// something here and that it will open later. It is a placeholder, not an
/// error — nothing has gone wrong, and it must not read as though it has.
class MessageLockedBody extends StatelessWidget {
  final ThemeState themeState;

  const MessageLockedBody({super.key, required this.themeState});

  @override
  Widget build(BuildContext context) {
    final color = themeState.textQuaternary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: color),
          Flexible(
            child: Text(
              'Encrypted — you do not have the key for this yet',
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                fontStyle: FontStyle.italic,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
