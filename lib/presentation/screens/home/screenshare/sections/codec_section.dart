import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// Section for selecting video codec, with a line saying what the chosen one
/// suits.
class CodecSection extends StatelessWidget {
  /// The codec the share would go out in, which may not be the saved one
  /// (`ScreenShareSettings.codecToSend`).
  final String selectedCodec;

  /// What this computer can send, in the order shown.
  final List<String> offered;
  final ValueChanged<String> onChanged;

  const CodecSection({
    super.key,
    required this.selectedCodec,
    required this.offered,
    required this.onChanged,
  });

  static String _explain(String codec) => switch (codec) {
    'H264' => 'Best for games and video.',
    'VP8' => 'Best for older devices.',
    _ => 'Best for text and slides.',
  };

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Codec',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: offered
              .map(
                (c) => SettingsChip(
                  label: c,
                  active: selectedCodec == c,
                  onTap: () => onChanged(c),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        Text(
          _explain(selectedCodec),
          style: AppText.secondary.copyWith(color: context.theme.textTertiary),
        ),
      ],
    );
  }
}
