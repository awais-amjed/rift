import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/ducking_preference.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// One line saying what Windows does to other apps during calls right now,
/// read from Windows itself, so it changes as soon as the person does.
class DuckingStatus extends StatelessWidget {
  final DuckingPreference preference;

  const DuckingStatus({super.key, required this.preference});

  @override
  Widget build(BuildContext context) {
    final off = preference == DuckingPreference.off;
    final color = off ? CustomColors.success : CustomColors.warning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            off ? Icons.check_circle_rounded : Icons.volume_down_rounded,
            size: K.iconButton,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'During calls, Windows ${preference.effect}.',
            style: AppText.secondaryStrong.copyWith(
              color: context.theme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
