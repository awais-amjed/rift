import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// The system tray icon — the way back to a window the user has closed.
///
/// One owner rather than a mixin. tray_manager 0.5 handed every click to
/// every registered `TrayListener`, so both the app shell and the title bar
/// implemented the same two menu items: one closed the window on Quit and the
/// other destroyed it, and whichever ran first decided what Quit meant. 0.7
/// puts the listener on the `TrayIcon` itself, which makes a single owner the
/// natural shape as well as the correct one.
///
/// Desktop only, and quiet when it cannot run: a Linux session with no status
/// area hands back no icon, and the app has to keep working without one — the
/// tray is a convenience, never the only route to anything.
class TrayService {
  TrayService._();

  static final TrayService instance = TrayService._();

  TrayIcon? _icon;

  /// Everything the icon refers to by native handle.
  ///
  /// `Image`, `Menu` and `MenuItem` each free their handle when the Dart
  /// object is collected, and the tray holds only the handle — so an item
  /// built and dropped inside a local is a menu row whose native half is
  /// freed at the next GC, while the tray still points at it. These live as
  /// long as the icon does.
  final List<Object> _retained = [];

  /// Whether a tray icon actually exists. False on a desktop without one.
  bool get isShowing => _icon != null;

  Future<void> init() async {
    if (_icon != null) return;

    final icon = TrayIcon.create();
    if (icon == null) return;

    final image = ImageAsset.fromAsset(
      'assets/images/${Platform.isWindows ? 'tray_icon.ico' : 'tray_icon.png'}',
    );
    if (image != null) {
      _retained.add(image);
      icon.icon = image;
    }
    icon.setTooltip('Rift');

    final menu = Menu.create();
    if (menu != null) {
      _retained.add(menu);
      _addItem(menu, 'Show Rift', _show);
      menu.addSeparator();
      _addItem(menu, 'Quit', windowManager.destroy);
      icon.setContextMenu(menu);
    }

    // A left click reopens the window, which is the only thing anyone wants
    // from this icon. The right click opens the menu by itself. Linux reports
    // neither — its panel keeps the click and opens the menu on its own.
    icon.addListener((event) {
      if (event is TrayIconClickedEvent) _show();
    });

    icon.setVisible(true);
    _icon = icon;
  }

  /// Adds one clickable row, carrying its own action.
  ///
  /// The 0.5 API identified a clicked item by a string key matched in a
  /// switch somewhere else, so a typo in either was a row that silently did
  /// nothing. Here the row and what it does are the same expression.
  void _addItem(Menu menu, String label, void Function() onClick) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) return;
    _retained.add(item);
    item.addListener((event) {
      if (event is MenuItemClickedEvent) onClick();
    });
    menu.addItem(item);
  }

  Future<void> _show() async {
    await windowManager.show();
    await windowManager.focus();
  }
}
