import 'package:flutter/material.dart';

import '../../../theme/theme_context.dart';

/// The rule between two sections of a settings page.
///
/// Every page uses it, so the pages read as one set. Voice & audio had rules
/// between its sections and the pages beside it had plain gaps, which made the
/// same kind of page look like two.
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Divider(color: context.theme.borderPrimary),
        const SizedBox(height: 16),
      ],
    );
  }
}
