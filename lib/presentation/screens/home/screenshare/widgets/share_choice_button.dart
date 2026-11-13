import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One of the first page's quality chips: a size, and its frame rate under it.
class ShareChoiceButton extends StatelessWidget {
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  final double height;

  const ShareChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.sub,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return SizedBox(
      height: height,
      child: Semantics(
        selected: selected,
        child: SelectableSurface(
          selected: selected,
          onTap: onTap,
          borderRadius: BorderRadius.circular(K.radiusRow),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: selected ? AppText.row : AppText.rowQuiet,
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.secondary.copyWith(
                  color: selected ? theme.textSecondary : theme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
