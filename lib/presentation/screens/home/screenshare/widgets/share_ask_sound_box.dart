import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/app_switch.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Asks about a window's sound this once, where its app has one remembered.
///
/// Unlike `CheckboxRow` it is only as wide as its words, to sit under the sound
/// switch with Advanced beside them.
class ShareAskSoundBox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ShareAskSoundBox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'For a window: ask, instead of using its last sound',
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 10,
            children: [
              // As wide as the switch above, so the two labels line up.
              SizedBox(
                width: AppSwitch.desktopTrackWidth,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              Text(
                'Ask which sound',
                style: AppText.secondary.copyWith(
                  color: context.theme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
