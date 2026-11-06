import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import 'share_choice_button.dart';
import 'share_choice_grid.dart';

/// The picture's size and frame rate as one choice: the common pairs, and a
/// Custom chip while Advanced holds something else.
class ShareQualityRow extends StatelessWidget {
  final ScreenShareSettings settings;
  final ValueChanged<ScreenShareSettings> onChanged;

  /// The Custom chip was pressed: where its value is changed is Advanced.
  final VoidCallback onCustom;

  const ShareQualityRow({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onCustom,
  });

  /// 120 fps stays in Advanced: it is for a game, on a computer that can take
  /// it, and a one-click way there would be pressed by people it stutters for.
  static const presets = [
    (height: 720, fps: 30),
    (height: 720, fps: 60),
    (height: 1080, fps: 60),
    (height: 1440, fps: 60),
    (height: 2160, fps: 60),
  ];

  static const _height = 52.0;

  /// Whether [settings] goes out as one of [presets].
  static bool isPreset(ScreenShareSettings settings) => presets.any(
    (p) => p.height == settings.resolution && p.fps == settings.fpsToSend,
  );

  @override
  Widget build(BuildContext context) {
    final custom = !isPreset(settings);
    return ShareChoiceGrid(
      columns: presets.length + (custom ? 1 : 0),
      // Room for the Custom chip's "1080p 120".
      minWidth: 84,
      children: [
        for (final preset in presets)
          ShareChoiceButton(
            label: ScreenShareSettings.labelFor(preset.height),
            sub: '${preset.fps} fps',
            height: _height,
            largeSub: true,
            selected:
                preset.height == settings.resolution &&
                preset.fps == settings.fpsToSend,
            onTap: () => onChanged(
              settings.copyWith(resolution: preset.height, fps: preset.fps),
            ),
          ),
        if (custom)
          ShareChoiceButton(
            label: 'Custom',
            sub: '${settings.resolutionLabel} ${settings.fpsToSend}',
            height: _height,
            largeSub: true,
            selected: true,
            onTap: onCustom,
          ),
      ],
    );
  }
}
