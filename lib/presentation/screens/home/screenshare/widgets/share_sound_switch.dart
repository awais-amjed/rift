import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/app_switch.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Whether a share carries sound, pressed anywhere on the row.
class ShareSoundSwitch extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const ShareSoundSwitch({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 11, 10, 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            AppSwitch(value: on, onChanged: (_) => onTap()),
            Text(
              'Share sound',
              style: AppText.body.copyWith(color: context.theme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
