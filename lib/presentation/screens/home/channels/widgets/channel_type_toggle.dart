import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/channel_type.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';

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
    return Row(
      children: [
        _TypeButton(
          icon: Icons.tag,
          label: 'Text',
          selected: value == ChannelType.text,
          onTap: onChanged == null ? null : () => onChanged!(ChannelType.text),
        ),
        const SizedBox(width: 8),
        _TypeButton(
          icon: Icons.volume_up,
          label: 'Voice',
          selected: value == ChannelType.voice,
          onTap: onChanged == null ? null : () => onChanged!(ChannelType.voice),
        ),
      ],
    );
  }
}

class _TypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _TypeButton({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SelectableSurface(
        selected: selected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusRow),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 7,
          children: [
            Icon(icon, size: 15),
            Text(label, style: selected ? AppText.row : AppText.rowQuiet),
          ],
        ),
      ),
    );
  }
}
