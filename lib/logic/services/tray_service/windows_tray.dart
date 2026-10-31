import 'package:flutter/services.dart';

/// The tray icon on Windows, which lives in the runner (`tray_icon.cpp`).
///
/// A window belongs to the thread that made it and hears nothing unless that
/// thread runs a message loop. Dart's thread on Windows does not (AGENTS.md,
/// *On Windows, Dart is not on the main thread*), so an icon made from here by
/// FFI, as tray_manager does, is drawn and never hears a click.
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
