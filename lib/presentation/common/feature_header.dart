import 'package:flutter/material.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';

/// The hero block that opens a full-screen step or a first-run panel: an
/// accent-tinted icon badge, a title, and an optional explanatory line.
///
/// Onboarding and the backup flows all opened with a hand-rolled copy of this;
/// keeping it in one place is what makes them stay consistent as the accent
/// palette changes.
class FeatureHeader extends StatelessWidget {
  static const double _badgeSize = 60;
  static const double _iconSize = 28;

  final IconData icon;
  final String title;
  final String? subtitle;
  final ThemeState themeState;

  /// Tints the badge. Defaults to the accent; the privacy-vault step passes
  /// green, because there the badge is making a claim about safety rather
  /// than naming a step.
  final Color? badgeColor;

  /// Keeps the explanatory line to a readable measure. Pass
  /// [double.infinity] where the surrounding panel already constrains it.
  final double subtitleMaxWidth;

  const FeatureHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.themeState,
    this.subtitle,
    this.badgeColor,
    this.subtitleMaxWidth = 340,
  });

  @override
  Widget build(BuildContext context) {
    final accent = badgeColor ?? themeState.accentBright;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _badgeSize,
          height: _badgeSize,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            // The ring is what stops the badge dissolving into the card at
            // this tint — a 10% wash on a translucent panel is barely there.
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          child: Icon(icon, size: _iconSize, color: accent),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppText.pageTitle.copyWith(color: themeState.textPrimary),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: subtitleMaxWidth),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppText.secondary.copyWith(
                height: 1.6,
                color: themeState.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
