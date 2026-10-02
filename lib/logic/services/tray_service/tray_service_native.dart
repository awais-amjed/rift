import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../before_quit.dart';

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
///
/// It also owns quitting on Windows, because the icon has to go first there:
/// the native tray keeps a function-local static it touches when an icon is
/// destroyed, and at exit that static is torn down before the handle table
/// that still owns the icon — so an icon left for exit to destroy crashed
/// every quit. Freed while the app is still running, it goes quietly.
class TrayService with WindowListener {
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

  /// A second Quit while the first is saving does nothing.
  bool _quitting = false;

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
      _addItem(menu, 'Quit', quit);
      icon.setContextMenu(menu);
      // The trigger defaults to none, which leaves the menu — and Quit —
      // unreachable. Windows opens it on a right click. Linux has to say
      // "clicked": only then does the StatusNotifierItem advertise its menu
      // (`ItemIsMenu`, and `Menu` pointing at it rather than at `/`), and the
      // panel opens it on any click. Under none, GNOME's AppIndicator panel
      // found no menu and the icon did nothing at all.
      if (Platform.isWindows) {
        icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      } else if (Platform.isLinux) {
        icon.setContextMenuTrigger(ContextMenuTrigger.clicked);
      }
    }

    // A left click reopens the window, which is the only thing anyone wants
    // from this icon. Linux reports neither click — the item answers
    // `Activate` without telling anyone — so there it is the menu's Show Rift.
    icon.addListener((event) {
      if (event is TrayIconClickedEvent) _show();
    });

    icon.setVisible(true);
    _icon = icon;

    // Closing the window any other way — Alt+F4, GNOME's Super+Q, the
    // taskbar's Close — does what the title bar's close button does: hide to
    // the tray, where Quit is. Left to the desktop it would end the process
    // with the icon still alive (Windows) and without [BeforeQuit] (both).
    // Only here, after an icon exists: without one a hidden window could
    // never come back, so the desktop's close stays a close.
    if (Platform.isWindows || Platform.isLinux) {
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    }
  }

  /// Leaves the app: out of sight at once, then [BeforeQuit]'s work, then the
  /// icon, then the window.
  ///
  /// Windows closes rather than destroys. window_manager's `destroy` there is
  /// a bare `PostQuitMessage`, which ends the message loop with the Flutter
  /// window still open, so the engine is torn down after `wWinMain` has
  /// returned and faults in flutter_windows.dll. A close goes through
  /// WM_DESTROY, which shuts the engine down while the loop still runs.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    await windowManager.hide();
    await BeforeQuit.instance.run();
    if (!Platform.isWindows) return windowManager.destroy();
    final icon = _icon;
    _icon = null;
    icon?.dispose();
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  /// The desktop asked the window to close. Hidden like the title bar's
  /// close button, while there is an icon to come back from.
  @override
  void onWindowClose() {
    if (_icon == null) {
      unawaited(quit());
      return;
    }
    unawaited(windowManager.hide());
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
