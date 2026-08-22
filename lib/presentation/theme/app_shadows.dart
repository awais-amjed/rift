import 'package:flutter/material.dart';

/// The app's depth scale.
///
/// Depth is how the redesign says "this floats over that": a dialog casts more
/// shadow than a popover, which casts more than a button. Hand-rolled
/// `BoxShadow`s drift apart, so every elevated surface reads its shadow here.
///
/// These are palette-independent — shadow is cast light, not a themed colour —
/// except [accentGlow], which takes the accent it should glow with.
class AppShadows {
  /// Modal dialogs: the heaviest surface in the app.
  static const List<BoxShadow> dialog = [
    BoxShadow(color: Color(0x99000000), blurRadius: 70, offset: Offset(0, 24)),
  ];

  /// A side pane overlaid on the content instead of docked beside it. Sits
  /// between [dialog] and [popover]: it covers most of the window like a
  /// dialog, but it is chrome rather than something you have to answer, so it
  /// should not read as heavily.
  static const List<BoxShadow> overlayPane = [
    BoxShadow(color: Color(0x94000000), blurRadius: 60, offset: Offset(0, 20)),
  ];

  /// Popovers and context menus.
  static const List<BoxShadow> popover = [
    BoxShadow(color: Color(0x8C000000), blurRadius: 50, offset: Offset(0, 16)),
  ];

  /// The message hover toolbar and other small floating chrome.
  static const List<BoxShadow> floatingBar = [
    BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 6)),
  ];

  /// The voice control pill, which floats over live video.
  static const List<BoxShadow> voicePill = [
    BoxShadow(color: Color(0x80000000), blurRadius: 40, offset: Offset(0, 12)),
  ];

  /// Cast under primary/action buttons so they read as lit, not just filled.
  static List<BoxShadow> accentGlow(
    Color accent, {
    double blurRadius = 16,
    double dy = 3,
  }) => [
    BoxShadow(
      color: accent.withValues(alpha: 0.3),
      blurRadius: blurRadius,
      offset: Offset(0, dy),
    ),
  ];

  /// The ring around a speaking participant's avatar or tile. Two stops: a
  /// hard ring plus the bloom around it.
  static List<BoxShadow> speakingRing(
    Color accent, {
    double t = 0,

    /// Scales the halo without touching the ring — a 22px avatar and a 16:9
    /// tile want the same hard edge but very different glows.
    double bloom = 1,
  }) {
    // `t` runs 0..1 over the pulse, widening the ring as the bloom softens.
    return [
      BoxShadow(
        color: accent.withValues(alpha: 0.9 - 0.25 * t),
        spreadRadius: 2 + 0.5 * t,
      ),
      BoxShadow(
        // Wider glows are spread over more area, so they need less alpha to
        // read at the same strength.
        color: accent.withValues(alpha: (0.35 - 0.1 * t) / bloom),
        blurRadius: (12 + 10 * t) * bloom,
        spreadRadius: (2 + 2 * t) * bloom,
      ),
    ];
  }
}
