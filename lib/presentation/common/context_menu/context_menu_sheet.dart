import 'package:flutter/material.dart';

import '../../theme/theme_context.dart';
import '../context_menu_region.dart';
import '../popover_surface.dart';
import '../sheet_handle.dart';

/// Tells the rows of a context menu that they are in a bottom sheet rather
/// than a floating panel, and gives a submenu row somewhere to open.
///
/// A phone has no pointer to hang a menu off and no room beside a panel for a
/// submenu, so the same menu is shown as a sheet instead: the rows grow to a
/// thumb's size, and a submenu replaces the menu in place with a way back.
/// The menus themselves don't change — every [ContextMenuPanel],
/// [ContextMenuItem] and [ContextMenuSubmenuItem] asks this how to draw
/// itself, so no action list is written twice.
class ContextMenuPresentation extends InheritedWidget {
  /// Shows [builder]'s menu in place of the one on screen.
  final void Function(WidgetBuilder builder) pushSubmenu;

  /// Back to the menu this one replaced. Null on the menu the sheet opened
  /// with, which has nothing behind it.
  final VoidCallback? popSubmenu;

  const ContextMenuPresentation({
    super.key,
    required this.pushSubmenu,
    required this.popSubmenu,
    required super.child,
  });

  /// Null in a floating menu — the desktop presentation, and the default.
  static ContextMenuPresentation? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContextMenuPresentation>();

  static bool isSheet(BuildContext context) => of(context) != null;

  @override
  bool updateShouldNotify(ContextMenuPresentation old) =>
      (popSubmenu == null) != (old.popSubmenu == null);
}

/// Shows [menu] as a bottom sheet — the phone's form of a context menu.
///
/// On the root navigator, so it covers a pushed page's own navigator as well
/// as the list under it. The menu's [ContextMenuScope] closes the sheet, so an
/// action that navigates away shuts it exactly as it would shut the popover.
Future<void> showContextMenuSheet(BuildContext context, Widget menu) {
  final theme = context.theme;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: theme.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PopoverSurface.radius),
      ),
    ),
    builder: (sheetContext) => _ContextMenuSheet(
      menu: menu,
      onDismiss: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

class _ContextMenuSheet extends StatefulWidget {
  final Widget menu;
  final VoidCallback onDismiss;

  const _ContextMenuSheet({required this.menu, required this.onDismiss});

  @override
  State<_ContextMenuSheet> createState() => _ContextMenuSheetState();
}

class _ContextMenuSheetState extends State<_ContextMenuSheet> {
  /// Submenus opened on top of the first menu, oldest first.
  final List<WidgetBuilder> _submenus = [];

  void _push(WidgetBuilder builder) => setState(() => _submenus.add(builder));

  void _pop() => setState(_submenus.removeLast);

  @override
  Widget build(BuildContext context) {
    final depth = _submenus.length;
    final menu = depth == 0 ? widget.menu : Builder(builder: _submenus.last);

    return PopScope(
      // Back inside a submenu goes back to its parent rather than closing the
      // whole sheet, the same as the arrow in its heading.
      canPop: depth == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              Flexible(
                child: SingleChildScrollView(
                  child: Material(
                    type: MaterialType.transparency,
                    child: ContextMenuScope(
                      dismiss: widget.onDismiss,
                      child: ContextMenuPresentation(
                        pushSubmenu: _push,
                        popSubmenu: depth == 0 ? null : _pop,
                        child: KeyedSubtree(key: ValueKey(depth), child: menu),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
