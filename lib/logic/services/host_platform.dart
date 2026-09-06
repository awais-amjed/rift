import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// What the surrounding operating system does and does not give us.
///
/// Kept apart from `LayoutMode`, which is only ever about how much room there
/// is. The two answer different questions and are wrong as substitutes for
/// each other: a phone-sized desktop window still has a title bar to draw and
/// no notch to avoid, and a tablet has neither of those and plenty of width.
class HostPlatform {
  const HostPlatform._();

  /// Whether the app draws its own window frame.
  ///
  /// The title bar is a *desktop* affordance — it carries the traffic lights,
  /// the drag region and the maximise toggle. A browser tab and a phone both
  /// already have their own chrome, and painting ours over them takes 38px
  /// off the top for a bar with nothing to do.
  ///
  /// Guarded on [kIsWeb] first because `dart:io`'s [Platform] throws on web.
  static bool get drawsOwnWindowChrome =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Whether the display has cutouts and system bars to keep clear of.
  ///
  /// Only ever a reason to *check* the insets, never to assume them — a
  /// `SafeArea` is harmless on a desktop, where they are all zero. This is for
  /// the cases where something more than padding changes.
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Whether a screen share can carry the computer's audio.
  ///
  /// Windows has WASAPI loopback and Linux has PulseAudio monitors; both are
  /// wired up in the Rust crate. macOS would need ScreenCaptureKit, which is
  /// not, so there the toggle is hidden and the share is video only rather
  /// than a toggle that does nothing.
  static bool get capturesSystemAudio =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Whether the OS lowers other applications' volume during a call, and lets
  /// us ask it not to.
  ///
  /// Windows does, through the audio session's ducking policy; nothing else
  /// Rift runs on has the behaviour or the switch. The settings pane hides the
  /// toggle entirely rather than showing one that does nothing.
  static bool get ducksOtherApps => !kIsWeb && Platform.isWindows;
}
