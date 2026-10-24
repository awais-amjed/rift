import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../../logic/services/open_link.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';

/// A line of accent text with the leave-the-app arrow, opening [url] in the
/// browser.
///
/// Words rather than an info icon: on a first screen people tap what they can
/// read, and the arrow says it goes out of the app before they find out.
///
/// It carries its own `Material` because an `InkWell` paints on the nearest
/// one *above* it, and the card this sits in fills its own background.
class ExternalLink extends StatelessWidget {
  final String label;
  final String url;

  const ExternalLink({super.key, required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => openExternalLink(url),
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Text(
                label,
                style: AppText.secondary.copyWith(
                  fontWeight: FontWeight.w500,
                  color: theme.accentBright,
                ),
              ),
              Icon(
                Icons.open_in_new_rounded,
                size: K.iconInline,
                color: theme.accentBright,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
