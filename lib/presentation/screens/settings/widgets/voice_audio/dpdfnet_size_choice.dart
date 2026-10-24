import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/segmented_control.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Which of DPDFNet's two models runs, shown while DPDFNet is the noise
/// filter. DPDFNet-2 is where it starts; DPDFNet-8 is for choosing, and
/// still goes over to DPDFNet-2 by itself on a computer too slow for it.
class DpdfnetSizeChoice extends StatelessWidget {
  final bool small;
  final ValueChanged<bool> onChanged;

  const DpdfnetSizeChoice({
    super.key,
    required this.small,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'DPDFNet model',
          style: AppText.row.copyWith(color: theme.textPrimary),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: K.settingsChoiceWidth / 3 * 2,
          ),
          child: SegmentedControl<bool>(
            value: small,
            onChanged: onChanged,
            options: const [
              SegmentOption(value: true, label: 'DPDFNet-2'),
              SegmentOption(value: false, label: 'DPDFNet-8'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          small
              ? 'Best beside a game, or on an older computer.'
              : 'Best for the most natural voice.',
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
      ],
    );
  }
}
