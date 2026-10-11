import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/ducking_preference.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/ducking/ducking_cubit.dart';
import '../../../../../logic/services/windows_sound_settings.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';
import 'ducking/ducking_status.dart';
import 'ducking/windows_ducking_choices.dart';

/// What Windows does to other apps' volume during a call, and how to change
/// it.
///
/// Says what Windows is set to now ([DuckingCubit], re-read when the window
/// comes back into focus), and walks through the change, since it is made in
/// Windows' own Sound window rather than here: the choice is Windows', covers
/// every calling app, and only takes effect at once when made there — see
/// [WindowsSoundSettings]. "Fix it" on the notice Rift shows when it
/// happens opens Settings here with [highlight] set.
///
/// Windows only; the Voice & Audio tab omits it elsewhere.
class AudioDuckingSection extends StatefulWidget {
  /// Scroll here and light the section up briefly, for someone who came
  /// from the notice.
  final bool highlight;

  const AudioDuckingSection({super.key, this.highlight = false});

  @override
  State<AudioDuckingSection> createState() => _AudioDuckingSectionState();
}

class _AudioDuckingSectionState extends State<AudioDuckingSection> {
  late bool _lit = widget.highlight;

  @override
  void initState() {
    super.initState();
    context.read<DuckingCubit>().refresh();
    if (!widget.highlight) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: AppMotion.enter,
        curve: AppMotion.arrive,
      );
      Future.delayed(AppMotion.linger * 2, () {
        if (mounted) setState(() => _lit = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final preference = context.select<DuckingCubit, DuckingPreference?>(
      (c) => c.state.preference,
    );
    final ducked = context.select<DuckingCubit, bool>((c) => c.state.ducked);
    final lowers = preference != null && preference != DuckingPreference.off;
    final body = AppText.secondary.copyWith(color: theme.textTertiary);

    // The glow sits behind the section, a little outside it, so lighting it
    // up does not move a line of what it says.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -12,
          right: -12,
          top: -12,
          bottom: -12,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: AppMotion.enter,
              curve: AppMotion.settle,
              decoration: BoxDecoration(
                color: _lit ? theme.channelActiveBg : Colors.transparent,
                borderRadius: BorderRadius.circular(K.radiusCard),
                border: Border.all(
                  color: _lit ? theme.channelActiveBorder : Colors.transparent,
                ),
              ),
            ),
          ),
        ),
        _content(context, preference, lowers, ducked, body),
      ],
    );
  }

  Widget _content(
    BuildContext context,
    DuckingPreference? preference,
    bool lowers,
    bool ducked,
    TextStyle body,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: "Other apps' volume during calls"),
        const SizedBox(height: 12),
        if (preference != null) ...[
          DuckingStatus(preference: preference),
          const SizedBox(height: 8),
        ],
        Text(
          lowers
              ? 'Windows does this for every calling app, not just Rift. Turn '
                    'it off if music or a game gets too quiet while you talk.'
              : 'Other apps keep their volume in calls, in Rift and in every '
                    'other calling app.',
          style: body,
        ),
        const SizedBox(height: 16),
        if (lowers) ...[
          const _Step(n: 1, text: 'Click Open Windows sound settings.'),
          const _Step(n: 2, text: 'In the window that opens, choose:'),
          Padding(
            padding: const EdgeInsets.only(left: 28, bottom: 8),
            child: WindowsDuckingChoices(current: preference),
          ),
          const _Step(
            n: 3,
            text:
                'Click OK. From your next call on, other apps keep their '
                'volume.',
          ),
          const SizedBox(height: 8),
        ] else ...[
          // Windows keeps a duck until the call's sound closes, whatever it
          // is set to by then (measured Oct 10 2026): someone who fixed it
          // mid-call would otherwise think it had not worked.
          if (ducked)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Windows keeps this call turned down until it ends. Leave '
                'and rejoin to get your other apps back to full volume now.',
                style: AppText.secondary.copyWith(
                  color: context.theme.textSecondary,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'To have Windows turn other apps down again, choose '
              '"${DuckingPreference.lowerBy80.windowsLabel}" there.',
              style: body,
            ),
          ),
        ],
        AppButton(
          label: 'Open Windows sound settings',
          onPressed: WindowsSoundSettings.openCommunicationsTab,
          variant: lowers
              ? AppButtonVariant.primary
              : AppButtonVariant.secondary,
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          title: 'Tell me when it happens',
          description: 'Best for noticing why other apps went quiet.',
          value: context.select<AppCubit, bool>((c) => c.state.showDuckingHint),
          onChanged: context.read<AppCubit>().setShowDuckingHint,
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;

  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.bgTertiary,
              shape: BoxShape.circle,
              border: Border.all(color: theme.borderPrimary),
            ),
            child: Text(
              '$n',
              style: AppText.meta.copyWith(color: theme.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppText.secondary.copyWith(color: theme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
