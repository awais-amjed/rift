import 'package:flutter/services.dart';

/// The tray icon on Windows, which lives in the runner (`tray_icon.cpp`).
///
/// A window belongs to the thread that made it and hears nothing unless that
/// thread runs a message loop. From Oct to Nov 2026 Dart had a thread of its
/// own on Windows, with no loop, so tray_manager's icon, made from Dart by
/// FFI, was drawn and never heard a click (beta.5 to beta.10). Dart is on the
/// window's thread again (AGENTS.md, *On Windows, Dart runs on the window's
/// thread*), but the runner's icon works whichever thread Dart is on, so it
/// stays.
class WindowsTray {
  WindowsTray({required this.onShow, required this.onQuit});

  static const MethodChannel channel = MethodChannel('rift/tray');

  final VoidCallback onShow;
  final VoidCallback onQuit;

  /// Puts the icon up, and answers whether there is one.
  Future<bool> add() async {
    channel.setMethodCallHandler(_onCall);
    try {
      return await channel.invokeMethod<bool>('add') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> remove() async {
    channel.setMethodCallHandler(null);
    await channel.invokeMethod<void>('remove');
  }

  Future<void> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'show':
        onShow();
      case 'quit':
        onQuit();
    }
  }
}
