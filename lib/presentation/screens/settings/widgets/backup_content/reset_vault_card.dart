import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// The reset-vault action, at the end of the Cloud Backup tab.
///
/// It used to sit at the bottom of the settings *nav*, which is the same
/// corner the gear that opens settings occupies on the screen behind — so a
/// second click, or one arriving after the screen had changed, landed on
/// wiping the identity. Anyone reaching for the gear again to close settings
/// hits it. Only the confirm dialog stood in the way.
///
/// Here it is unreachable until you have chosen the one tab it belongs with,
/// and it reads in the right order: back up your vault, restore your vault,
/// destroy your vault. That also answers the original objection to putting it
/// in the content pane — it is no longer sitting under whatever tab happened
/// to be open.
///
/// A bordered danger card rather than a text button: this wipes an identity
/// that cannot be recovered without a backup, and it should look like the one
/// thing on the screen you can't undo.
class ResetVaultCard extends StatelessWidget {
  final ThemeState themeState;
  final VoidCallback onTap;

  const ResetVaultCard({
    super.key,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(K.radiusCard);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        color: CustomColors.error.withValues(alpha: 0.08),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          hoverColor: CustomColors.error.withValues(alpha: 0.12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: CustomColors.error.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    const Icon(
                      Icons.delete_forever_rounded,
                      size: 16,
                      color: CustomColors.error,
                    ),
                    Text(
                      'Reset vault',
                      style: AppText.secondary.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CustomColors.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Wipes your keys and servers from this device.',
                  style: AppText.label.copyWith(
                    height: 1.35,
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
