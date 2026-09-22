import 'package:flutter/material.dart';

/// Colours for what is drawn over a picture — video, a photo, a blurred
/// image — or over the whole app to push it back.
///
/// Not themed, on purpose: what is underneath is somebody's camera or
/// screen, not a palette, and it is as dark in the light theme as in the
/// dark one. Themed values here would put dark text on a dark frame.
class MediaColors {
  /// The dim laid over the app behind a drawer or a sheet.
  static const Color scrim = Color(0x99000000);

  /// Behind a picture opened full-screen: dark enough that the picture is the
  /// only thing left to look at.
  static const Color viewerBarrier = Color(0xDD000000);

  /// A bar or a chip floating on video: a stats card, a Stop watching pill.
  static const Color panel = Color(0xB3000000);

  /// The viewer's toolbar strip — lighter than [panel], because it spans the
  /// picture rather than sitting in a corner of it.
  static const Color toolbar = Color(0x8C000000);

  /// Over a blurred image, just enough that white text reads on a light one.
  static const Color veil = Color(0x59000000);

  /// A video's own ground, so letterboxing reads as the edge of the picture.
  static const Color videoGround = Color(0xFF000000);

  // ── On media ──────────────────────────────────────────────
  static const Color onMedia = Color(0xFFFFFFFF);
  static const Color onMediaSecondary = Color(0xB3FFFFFF);
  static const Color onMediaTertiary = Color(0x8AFFFFFF);
  static const Color onMediaQuaternary = Color(0x61FFFFFF);
}
