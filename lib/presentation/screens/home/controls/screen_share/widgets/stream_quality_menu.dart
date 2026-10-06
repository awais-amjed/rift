import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/screen_share_settings.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import 'change_stream_quality.dart';

/// The running share's frame rate and height, the same choices the share
/// dialog offers. A pick applies at once and leaves the menu open; the
/// picture blinks for viewers while it is published again at the new size.
class StreamQualityMenu extends StatelessWidget {
  const StreamQualityMenu({super.key});

  static const double _width = 200;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return BlocBuilder<ScreenshareCubit, ScreenshareState>(
      buildWhen: (prev, curr) => prev.settings != curr.settings,
      builder: (context, state) {
        final settings = state.settings ?? const ScreenShareSettings();
        return ContextMenuPanel(
          heading: 'Frame rate',
          maxWidth: _width,
          children: [
            for (final fps in ScreenShareSettings.frameRatesAt(
              settings.resolution,
            ))
              _Choice(
                label: '$fps fps',
                chosen: settings.fps == fps,
                onTap: () => changeStreamQuality(context, fps: fps),
              ),
            Divider(height: 9, color: themeState.borderPrimary),
            const _SectionLabel('Resolution'),
            for (final height in ScreenShareSettings.resolutions)
              _Choice(
                label: ScreenShareSettings.labelFor(height),
                chosen: settings.resolution == height,
                onTap: () => changeStreamQuality(context, resolution: height),
              ),
          ],
        );
      },
    );
  }
}

/// One option, ticked when current — as the notification levels are.
class _Choice extends StatelessWidget {
  final String label;
  final bool chosen;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.chosen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ContextMenuItem(
    label: label,
    trailing: chosen ? const Icon(Icons.check_rounded, size: K.iconRow) : null,
    // Picking the current one again would republish for nothing.
    onTap: chosen ? () {} : onTap,
  );
}

/// A second heading partway down the panel, set like the panel's own.
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
    child: Text(
      text.toUpperCase(),
      style: AppText.sectionLabel.copyWith(color: context.theme.textTertiary),
    ),
  );
}
