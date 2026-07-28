import 'package:flutter/material.dart';

import '../../logic/cubits/theme/theme_cubit.dart';

/// The hero block that opens a full-screen step or a first-run panel: an
/// accent-tinted icon badge, a title, and an optional explanatory line.
///
/// Onboarding and the backup flows all opened with a hand-rolled copy of this;
/// keeping it in one place is what makes them stay consistent as the accent
/// palette changes.
class FeatureHeader extends StatelessWidget {
  static const double _badgeSize = 64;
  static const double _iconSize = 32;

  final IconData icon;
  final String title;
  final String? subtitle;
  final ThemeState themeState;

  /// 22 in onboarding steps; the denser dialogs use 20.
  final double titleSize;

  /// Keeps the explanatory line to a readable measure. Pass
  /// [double.infinity] where the surrounding panel already constrains it.
  final double subtitleMaxWidth;

  const FeatureHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.themeState,
    this.subtitle,
    this.titleSize = 22,
    this.subtitleMaxWidth = 380,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _badgeSize,
          height: _badgeSize,
          decoration: BoxDecoration(
            color: themeState.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: _iconSize, color: themeState.primary),
        ),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w700,
            color: themeState.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: subtitleMaxWidth),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: themeState.textTertiary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
