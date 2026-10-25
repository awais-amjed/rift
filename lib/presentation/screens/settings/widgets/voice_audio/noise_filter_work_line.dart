import 'package:flutter/material.dart';

import '../../../../../data/enums/noise_filter_work.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// What the noise suppression choice is waiting on, in place of the line
/// that says what the choice suits, so a pick that takes a moment is not
/// taken for one that did nothing.
class NoiseFilterWorkLine extends StatelessWidget {
  final NoiseFilterWork work;

  const NoiseFilterWorkLine({super.key, required this.work});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LoadingDots(color: theme.textTertiary, dotSize: 3),
        const SizedBox(width: 6),
        Text(switch (work) {
          NoiseFilterWork.loadingModel => 'Loading DPDFNet…',
          _ => 'Starting noise suppression…',
        }, style: AppText.secondary.copyWith(color: theme.textTertiary)),
      ],
    );
  }
}
