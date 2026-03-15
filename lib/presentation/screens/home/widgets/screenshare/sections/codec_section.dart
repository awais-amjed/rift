import 'package:flutter/material.dart';

import '../widgets/settings_chip.dart';
import '../widgets/settings_section.dart';

/// Section for selecting video codec
class CodecSection extends StatelessWidget {
  final String selectedCodec;
  final ValueChanged<String> onChanged;

  static const _codecOptions = ['VP8', 'H264', 'VP9'];

  const CodecSection({
    super.key,
    required this.selectedCodec,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Codec',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _codecOptions
              .map(
                (c) => SettingsChip(
                  label: c,
                  active: selectedCodec == c,
                  onTap: () => onChanged(c),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}
