import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A listed bot's source host, as a link out of the app.
///
/// It carries its own `Material` because an `InkWell` paints on the nearest
/// one *above* it, and the tile this sits in fills its own background — so
/// without this the highlight is drawn and then covered, and the only way to
/// find the link is to click it.
class BotSourceLink extends StatelessWidget {
  final String host;
  final VoidCallback? onTap;

  const BotSourceLink({super.key, required this.host, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final style = AppText.label.copyWith(
      fontWeight: FontWeight.w400,
      color: onTap == null ? theme.textTertiary : theme.accentBright,
    );
    if (onTap == null) return Text(host, style: style);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 3,
            children: [
              Text(host, style: style),
              Icon(
                Icons.open_in_new_rounded,
                size: 11,
                color: theme.accentBright,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
