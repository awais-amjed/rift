import 'package:flutter/material.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_dropdown.dart';
import '../widgets/settings_section.dart';

/// The share's codec, as a dropdown led by Auto.
class CodecSection extends StatelessWidget {
  /// The codec picked by hand, or null for Auto.
  final VideoCodec? chosen;

  /// What Auto would send (`ScreenShareSettings.codecToSend`), which it
  /// names in brackets.
  final VideoCodec auto;

  /// What this computer can send besides Auto, in the order shown.
  final List<VideoCodec> offered;

  /// Null is Auto.
  final ValueChanged<VideoCodec?> onChanged;

  const CodecSection({
    super.key,
    required this.chosen,
    required this.auto,
    required this.offered,
    required this.onChanged,
  });

  /// What the codec a share goes out in is best for.
  static String explain(VideoCodec codec) => switch (codec) {
    VideoCodec.h264 => 'Best for games and video.',
    VideoCodec.vp8 => 'Best for older devices.',
    VideoCodec.vp9 => 'Best for text and slides.',
  };

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      label: 'Codec',
      children: [
        AppDropdown<VideoCodec?>(
          value: chosen,
          options: [
            AppDropdownOption(
              value: null,
              label: 'Auto (${ScreenShareSettings.nameOf(auto)})',
            ),
            for (final codec in offered)
              AppDropdownOption(
                value: codec,
                label: ScreenShareSettings.nameOf(codec),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
