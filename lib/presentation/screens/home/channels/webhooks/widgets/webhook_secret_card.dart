import 'package:flutter/material.dart';

import '../../../../../../data/classes/webhook.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../../data/constants.dart';

/// The URL of a webhook that was just created — shown once, and then gone.
///
/// The warning is the point of the card. Everywhere else in this app a thing
/// you can see once you can see again; the server stores only a SHA-256 of this
/// URL, so there is no "show it again", and finding that out by closing the
/// dialog would be a bad way to learn it.
class WebhookSecretCard extends StatelessWidget {
  final WebhookSecret created;
  final ThemeState themeState;
  final bool copied;
  final VoidCallback onCopy;

  const WebhookSecretCard({
    super.key,
    required this.created,
    required this.themeState,
    required this.copied,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CustomColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: CustomColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 6,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 15,
                color: CustomColors.warning,
              ),
              Expanded(
                child: Text(
                  'Copy this now — it is shown once',
                  style: AppText.row.copyWith(
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          Text(
            'Anyone with this URL can post to this channel. The server keeps '
            'only a hash of it, so it cannot be shown again — if you lose it, '
            'revoke this webhook and make another.',
            style: AppText.meta.copyWith(color: themeState.textSecondary),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: themeState.bgPrimary,
              borderRadius: BorderRadius.circular(K.radiusRow),
              border: Border.all(color: themeState.borderElevated),
            ),
            child: SelectableText(
              created.url,
              style: AppText.meta.copyWith(
                fontFamily: 'monospace',
                color: themeState.textPrimary,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: copied ? 'Copied' : 'Copy URL',
              variant: AppButtonVariant.secondary,
              onPressed: onCopy,
              icon: Icon(
                copied ? Icons.check_rounded : Icons.copy_rounded,
                size: 14,
                color: themeState.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
