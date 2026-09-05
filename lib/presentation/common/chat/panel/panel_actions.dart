import 'package:flutter/material.dart';

import '../../../../data/classes/panel_block.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';

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

  /// A menu, drawn as Rift's own dropdown. The bot names the action once; each
  /// option carries the value that comes back with it.
  Widget _select(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: PopupMenuButton<PanelAction>(
        enabled: onAction != null,
        onSelected: (option) =>
            onAction!(block.action!, option.value ?? option.label),
        itemBuilder: (context) => [
          for (final option in block.actions)
            PopupMenuItem(value: option, child: Text(option.label)),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: themeState.bgHover,
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              Text(
                block.text ?? 'Choose…',
                style: AppText.secondary.copyWith(
                  color: themeState.textSecondary,
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 15,
                color: themeState.textTertiary,
              ),
            ],
          ),
        ),
      ),
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(K.radiusRow),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
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
    );
  }
}
