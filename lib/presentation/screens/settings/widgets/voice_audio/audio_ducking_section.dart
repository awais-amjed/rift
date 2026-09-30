import 'package:flutter/material.dart';

import '../../../../../logic/services/windows_sound_settings.dart';
import '../../../../common/app_button.dart';
import '../../../../common/button_footer.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

/// What Windows does to other apps' volume during a call, and where to change
/// it.
///
/// Explained and handed over rather than switched from here: the choice is
/// Windows' own, covers every calling app, and only takes effect at once when
/// made in Windows' Sound window — see [WindowsSoundSettings]. A toggle here
/// used to write the same setting and did nothing until the next sign-in.
///
/// Windows only; the Voice & Audio tab omits it elsewhere.
class AudioDuckingSection extends StatelessWidget {
  const AudioDuckingSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final body = AppText.secondary.copyWith(color: theme.textTertiary);
    final steps = AppText.secondary.copyWith(color: theme.textSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: "Other apps' volume during calls"),
        const SizedBox(height: 12),
        Text(
          'When a call starts, Windows turns down everything else that is '
          'playing — music, videos, games — so the call is easier to hear. '
          'This is called ducking. Windows does it for every calling app, '
          'not just Rift, and out of the box it lowers other sounds by 80%.',
          style: body,
        ),
        const SizedBox(height: 8),
        Text(
          'Turn it off if other apps get too quiet while you are in a call — '
          'music you want to keep hearing, or a game you are talking over.',
          style: body,
        ),
        const SizedBox(height: 8),
        Text(
          'To change it, click Open Windows sound settings. Windows opens its '
          'Sound window on the Communications tab: choose "Do nothing" and '
          'click OK. It applies straight away, to every app. To go back, '
          'choose "Reduce the volume of other sounds by 80%".',
          style: steps,
        ),
        const SizedBox(height: 12),
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            AppButton(
              label: 'Open Windows sound settings',
              onPressed: WindowsSoundSettings.openCommunicationsTab,
              variant: AppButtonVariant.secondary,
            ),
          ],
        ),
      ],
    );
  }
}
