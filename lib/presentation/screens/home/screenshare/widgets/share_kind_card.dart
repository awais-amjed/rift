import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One of the two things the share dialog opens on: an entire screen or a
/// window. Pressing it is the action, so there is nothing to confirm after.
class ShareKindCard extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Null while the other card's press is still being answered.
  final VoidCallback? onTap;

  const ShareKindCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  static const _height = 188.0;
  static const _iconSize = 44.0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusCard);
    return SizedBox(
      height: _height,
      child: Material(
        color: theme.bgTertiary,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: theme.borderPrimary),
        ),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          borderRadius: radius,
          hoverColor: theme.bgActive,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 14,
            children: [
              Icon(icon, size: _iconSize, color: theme.accentBright),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.panelTitle.copyWith(color: theme.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
