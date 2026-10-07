import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';

/// Sits above the composer while a staged file is set to go unencrypted, so
/// the choice is read before the message goes rather than after, the same
/// timing as [ComposerPlaintextNotice].
class ComposerPlainFileNotice extends StatelessWidget {
  final int count;
  const ComposerPlainFileNotice({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final files = count == 1 ? '1 file' : '$count files';
    final them = count == 1 ? 'it' : 'them';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: CustomColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: CustomColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            Icons.lock_open_rounded,
            size: K.iconInline,
            color: themeState.statusInk(CustomColors.warning),
          ),
          Expanded(
            child: Text(
              '$files will be sent unencrypted. The server can see $them.',
              style: AppText.meta.copyWith(color: themeState.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
