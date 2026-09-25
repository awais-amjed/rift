import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../common/app_button.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Empty state shown when no channels exist.
///
/// It carries the create button because the section headers that normally hold
/// one aren't drawn when there is nothing to head — which left a freshly
/// created server with no way at all to make its first channel.
class EmptyChannelsView extends StatelessWidget {
  /// Null for members who may not create channels: they get told to ask,
  /// rather than given a button that would fail.
  final VoidCallback? onCreate;

  const EmptyChannelsView({super.key, this.onCreate});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tag, size: 32, color: themeState.textQuaternary),
            const SizedBox(height: 8),
            Text(
              'No channels yet',
              style: AppText.rowQuiet.copyWith(color: themeState.textTertiary),
            ),
            const SizedBox(height: 4),
            Text(
              onCreate == null
                  ? 'An admin has to create the first one.'
                  : 'Create the first one to start talking.',
              textAlign: TextAlign.center,
              style: AppText.label.copyWith(
                fontWeight: FontWeight.w400,
                color: themeState.textTertiary,
              ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 14),
              AppButton(
                label: 'Create channel',
                icon: const Icon(Icons.add_rounded, size: K.iconRow),
                onPressed: onCreate,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
