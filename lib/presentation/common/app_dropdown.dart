import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'context_menu/context_menu_item.dart';
import 'context_menu/context_menu_overlay.dart';
import 'context_menu/context_menu_panel.dart';

/// One choice in an [AppDropdown].
class AppDropdownOption<T> {
  final T value;
  final String label;

  /// Beside the label, in the menu and on the field while it is the choice —
  /// a region's load, say.
  final Widget? trailing;

  const AppDropdownOption({
    required this.value,
    required this.label,
    this.trailing,
  });
}

/// A choice from a short list, drawn as one of the app's fields and opening
/// the app's own menu.
///
/// Material's dropdown was the last control here in its default dress: an
/// outlined box that matched no other field, and a menu with its own rows,
/// radius and highlight that matched no other menu. This is the field every
/// text box is — same fill, border and height — and the menu every
/// right-click opens, the width of the field, under it. A phone gets that
/// menu as a sheet, like every other menu there.
class AppDropdown<T> extends StatefulWidget {
  final T value;
  final List<AppDropdownOption<T>> options;

  /// Null greys the field out and leaves it shut.
  final ValueChanged<T>? onChanged;

  /// A glyph at the field's start, where it says what kind of thing this is
  /// faster than the label does — a microphone beside the speakers.
  final IconData? icon;

  /// Shown when [value] matches none of [options].
  final String hint;

  const AppDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.icon,
    this.hint = 'Choose…',
  });

  /// The most a menu grows before its rows scroll: a device list can be long.
  static const double menuMaxHeight = 320;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final ContextMenuOverlay _menu = ContextMenuOverlay();

  AppDropdownOption<T>? get _selected {
    for (final option in widget.options) {
      if (option.value == widget.value) return option;
    }
    return null;
  }

  bool get _enabled => widget.onChanged != null && widget.options.isNotEmpty;

  @override
  void dispose() {
    _menu.dismiss();
    super.dispose();
  }

  void _open() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // Under the field, left edges together, the field's own width.
    final below = box.localToGlobal(Offset(0, box.size.height + 4));
    _menu.show(context, _buildMenu(box.size.width), below);
  }

  void _pick(T value) {
    _menu.dismiss();
    if (value != widget.value) widget.onChanged?.call(value);
  }

  Widget _buildMenu(double width) {
    final themeState = context.theme;
    return ContextMenuPanel(
      maxWidth: width,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: AppDropdown.menuMaxHeight,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in widget.options)
                  ContextMenuItem(
                    label: option.label,
                    onTap: () => _pick(option.value),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 8,
                      children: [
                        ?option.trailing,
                        // The current choice says so, as a check on the
                        // right rather than a tint that reads as hover.
                        Icon(
                          Icons.check_rounded,
                          size: K.iconRow,
                          color: option.value == widget.value
                              ? themeState.accentBright
                              : Colors.transparent,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final selected = _selected;
    final radius = BorderRadius.circular(K.radiusRow);

    return Opacity(
      opacity: _enabled ? 1 : 0.5,
      child: Container(
        height: K.fieldHeight,
        decoration: BoxDecoration(
          color: themeState.bgTertiary,
          borderRadius: radius,
          border: Border.all(color: themeState.borderElevated),
        ),
        // Inside the fill, or the hover is painted under it — see AGENTS.md.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: radius,
            hoverColor: themeState.bgHover,
            onTap: _enabled ? _open : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                spacing: 8,
                children: [
                  if (widget.icon case final icon?)
                    Icon(icon, size: K.iconRow, color: themeState.textTertiary),
                  Expanded(
                    child: Text(
                      selected?.label ?? widget.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowQuiet.copyWith(
                        color: selected == null
                            ? themeState.textTertiary
                            : themeState.textPrimary,
                      ),
                    ),
                  ),
                  ?selected?.trailing,
                  Icon(
                    Icons.expand_more_rounded,
                    size: K.iconButton,
                    color: themeState.textQuaternary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
