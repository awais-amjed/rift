import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';

/// A short word in a tinted pill: a role beside a name, a Bot tag, a Banned
/// mark. One recipe for all of them, so a tag reads as a tag wherever it is.
///
/// Uncoloured pills use the neutral fill; a coloured one washes its colour
/// behind the word at 16% and writes the word in it.
///
/// Always uppercase, whoever passes the word. Role chips uppercased
/// themselves and the rest did not, so one member row read "Bot" beside
/// "OWNER · ADMIN", and a profile listed roles in a case the sidebar never
/// showed them in.
class LabelPill extends StatelessWidget {
  final String label;
  final Color? color;
  const LabelPill({super.key, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final colour = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colour == null
            ? themeState.bgHover
            : colour.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(K.radiusPill),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppText.roleChip.copyWith(
          color: colour ?? themeState.textTertiary,
        ),
      ),
    );
  }
}
