import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One option of the share dialog's selection rows: a label, and under it what
/// the option comes to where that is worth saying (Auto's codec, a preset's
/// frame rate).
///
/// [onTap] null is an option this share cannot use, 120 fps at 4K or a bitrate
/// over the server's limit: greyed rather than left out, so the rows keep their
/// shape and the reason is there to be seen.
class ShareChoiceButton extends StatelessWidget {
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback? onTap;
  final double height;

  /// [sub] in the larger small size, for the taller quality chips.
  final bool largeSub;

  const ShareChoiceButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.sub,
    this.height = K.controlHeight,
    this.largeSub = false,
  });

  static const _greyed = 0.4;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final under = sub;
    final button = SizedBox(
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
              if (under != null)
                Text(
                  under,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (largeSub ? AppText.secondary : AppText.meta).copyWith(
                    color: selected ? theme.textSecondary : theme.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return onTap == null ? Opacity(opacity: _greyed, child: button) : button;
  }
}
