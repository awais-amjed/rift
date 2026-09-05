import 'package:flutter/material.dart';

import '../../../../data/classes/panel_block.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// Key/value rows — a queue length, a score, a build number.
///
/// A table rather than a wrap: these are read down the labels, and a layout
/// that reflows them by width turns "3 items" into a puzzle about which label
/// it belongs to.
class PanelFields extends StatelessWidget {
  final List<PanelField> fields;

  const PanelFields({super.key, required this.fields});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final field in fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(
                      field.label,
                      style: AppText.meta.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      field.value,
                      style: AppText.secondary.copyWith(
                        color: themeState.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
