import 'package:flutter/material.dart';

import '../../../../../data/enums/channel_type.dart';
import '../../../../common/segmented_control.dart';

/// The text/voice segmented control.
class ChannelTypeToggle extends StatelessWidget {
  final ChannelType value;
  final ValueChanged<ChannelType>? onChanged;

  const ChannelTypeToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedControl<ChannelType>(
      value: value,
      onChanged: onChanged,
      options: const [
        SegmentOption(value: ChannelType.text, label: 'Text', icon: Icons.tag),
        SegmentOption(
          value: ChannelType.voice,
          label: 'Voice',
          icon: Icons.volume_up,
        ),
      ],
    );
  }
}
