import 'package:flutter/material.dart';

import '../../../../data/classes/panel_block.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';
import 'panel_select.dart';

/// The pressable half of a panel: a row of buttons, or a menu.
///
/// A bot picks the *weight* of an action and not its colour, so a panel cannot
/// paint itself into looking like part of Rift's own chrome — a fake "Sign in"
/// in the app's accent is exactly the thing a declarative block set exists to
/// make impossible.
///
/// Buttons wrap rather than scroll. A bot that offers nine of them has made a
/// menu, and a horizontal scroller would hide the ninth on a phone with no
/// sign that it was there.
class PanelActions extends StatelessWidget {
  final PanelBlock block;
  final void Function(String action, String? value)? onAction;

  const PanelActions({super.key, required this.block, this.onAction});

  bool get _isSelect => block.type == PanelBlockType.select;

  @override
  Widget build(BuildContext context) {
    if (_isSelect) return _select(context);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final action in block.actions)
            _Button(
              action: action,
              onTap: onAction == null
                  ? null
                  : () => onAction!(action.action, action.value),
            ),
        ],
      ),
    );
  }

  Widget _select(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: PanelSelect(block: block, onAction: onAction),
    );
  }
}

class _Button extends StatelessWidget {
  final PanelAction action;
  final VoidCallback? onTap;

  const _Button({required this.action, this.onTap});

  Color _foreground(BuildContext context) => switch (action.style) {
    PanelButtonStyle.primary => context.theme.accentBright,
    PanelButtonStyle.danger => CustomColors.error,
    PanelButtonStyle.normal => context.theme.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: action.style == PanelButtonStyle.normal
            ? themeState.bgHover
            : _foreground(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          borderRadius: BorderRadius.circular(K.radiusRow),
          // A fixed height and the label's own width. A Container with an
          // alignment grows to every pixel it is offered, which in a Wrap is
          // the whole card.
          child: SizedBox(
            height: K.compactControlHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Center(
                widthFactor: 1,
                child: Text(
                  action.label,
                  style: AppText.secondary.copyWith(
                    color: _foreground(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
