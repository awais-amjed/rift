import 'package:flutter/material.dart';

import '../../../../common/segmented_control.dart';

/// Whether the share is a whole screen or one window.
class CaptureTypeSection extends StatelessWidget {
  final bool captureFullScreen;
  final ValueChanged<bool> onChanged;

  const CaptureTypeSection({
    super.key,
    required this.captureFullScreen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedControl<bool>(
      value: captureFullScreen,
      onChanged: onChanged,
      options: const [
        SegmentOption(
          value: true,
          label: 'Screen',
          icon: Icons.desktop_windows_outlined,
        ),
        SegmentOption(
          value: false,
          label: 'Window',
          icon: Icons.web_asset_rounded,
        ),
      ],
    );
  }
}
