import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/segmented_control.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Which of DPDFNet's two models runs, shown while DPDFNet is the noise
/// filter. DPDFNet-8 still goes over to DPDFNet-2 by itself on a computer
/// too slow for it; this is for choosing DPDFNet-2 outright.
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
              SegmentOption(value: false, label: 'DPDFNet-8'),
              SegmentOption(value: true, label: 'DPDFNet-2'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          small
              ? 'Best for an older or busy computer.'
              : 'Best for the most natural voice.',
          style: AppText.secondary.copyWith(color: theme.textTertiary),
        ),
      ],
    );
  }
}
