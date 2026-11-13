import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Outlined, and quieter than the cards: it is for those who go looking.
class ShareAdvancedButton extends StatelessWidget {
  final String summary;
  final VoidCallback onTap;

  const ShareAdvancedButton({
    super.key,
    required this.summary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: theme.borderPrimary),
      ),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          height: K.controlHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Icon(Icons.tune, size: K.iconRow, color: theme.textSecondary),
                Text(
                  'Advanced',
                  style: AppText.rowQuiet.copyWith(color: theme.textSecondary),
                ),
                Flexible(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.secondary.copyWith(
                      color: theme.textTertiary,
                    ),
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
