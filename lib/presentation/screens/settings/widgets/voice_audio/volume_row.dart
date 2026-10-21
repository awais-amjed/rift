import 'package:flutter/material.dart';

import '../../../../common/volume_readout.dart';
import '../../../../common/volume_slider.dart';
import '../../../../theme/app_text.dart';

/// A volume in Voice & Audio: the slider, and what it reads beside it.
class VolumeRow extends StatelessWidget {
  final double value;
  final double max;
  final ValueChanged<double> onChanged;

  const VolumeRow({
    super.key,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: VolumeSlider(value: value, max: max, onChanged: onChanged),
        ),
        // Wide enough for "200%", so dragging never shifts the track.
        VolumeReadout(
          value: value,
          style: AppText.meta,
          width: 40,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
