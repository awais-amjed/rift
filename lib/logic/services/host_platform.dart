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

  /// A native desktop build: Windows, Linux or macOS. Where the app is a
  /// window that stays running, so it tells the user things itself rather
  /// than being woken by a push to do it.
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Whether a screen share can carry the computer's audio.
  ///
  /// Windows has WASAPI loopback and Linux has PulseAudio monitors; both are
  /// wired up in the Rust crate. macOS would need ScreenCaptureKit, which is
  /// not, so there the toggle is hidden and the share is video only rather
  /// than a toggle that does nothing.
  static bool get capturesSystemAudio =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Whether WebRTC records the mic through the OS's own echo canceller.
  ///
  /// On Windows it does whenever echo cancellation is on, and that canceller
  /// gives no microphone audio while nothing is played out — which WebRTC
  /// does not allow for. See `_CaptureReviveMixin` in the LiveKit cubit.
  static bool get recordsThroughOsEchoCanceller =>
      !kIsWeb && Platform.isWindows;

  /// Whether the OS lowers other applications' volume during a call.
  ///
  /// Windows does, and keeps the choice in its own Sound window; nothing else
  /// Rift runs on has the behaviour. The settings pane explains it and opens
  /// that window there, and shows nothing about it elsewhere.
  static bool get ducksOtherApps => !kIsWeb && Platform.isWindows;

  /// Whether push-to-talk can be offered at all.
  ///
  /// Windows has a keyboard hook that sees the key in any app. Linux has the
  /// desktop's GlobalShortcuts portal for that, and falls back to the key
  /// working only while Rift is focused where the portal is missing. macOS
  /// would need an accessibility-permission event tap, which is not built.
  static bool get hasPushToTalk =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  /// Whether push-to-talk asks the desktop for the key, through the
  /// GlobalShortcuts portal, rather than taking it with a hook — so there is a
  /// one-time permission prompt to warn about.
  static bool get pushToTalkAsksDesktop => !kIsWeb && Platform.isLinux;

  // ── Screen share ──────────────────────────────────────────

  /// Whether the share's source is chosen in Rift's own dialog.
  ///
  /// Linux asks the system portal at capture time instead, so there is no
  /// list to show up front and nothing to require before starting.
  static bool get picksShareSourceInApp => !kIsWeb && !Platform.isLinux;

  /// Whether the source list can show a thumbnail of each window. Only the
  /// Windows capturer produces them.
  static bool get hasShareThumbnails => !kIsWeb && Platform.isWindows;

  /// Whether sharing one window's audio needs a PulseAudio source picked by
  /// hand. Full-screen capture uses loopback everywhere, and Windows finds a
  /// window's audio by its process.
  static bool get picksShareAudioSource => !kIsWeb && Platform.isLinux;

  /// Whether an audio source's `index` is a process id rather than a
  /// PulseAudio sink input. Windows lists what is playing by process and
  /// captures one by its id; Linux lists sink inputs.
  static bool get listsAudioSourcesByProcess => !kIsWeb && Platform.isWindows;
}
