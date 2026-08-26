import 'package:flutter/animation.dart';

/// The app's motion scale.
///
/// Curves are Flutter's, so they live here. Durations mostly live in `K` beside
/// the geometry they move — a panel's travel time belongs next to its width —
/// but the ones below belong to no geometry at all: they are how long a *kind*
/// of change takes, wherever it happens. They are named for the job rather than
/// the length, because that is the decision at a call site: is this a control
/// answering the pointer, or something arriving that the user did not do?
/// Giving those two the same length is what makes an interface feel either
/// sluggish or twitchy.
///
/// The rule the numbers encode: **nothing the user is waiting on runs longer
/// than [state].** Motion is for making a change legible, not for making it an
/// event.
class AppMotion {
  const AppMotion._();

  /// Panels opening and closing. Decelerating, so the panel arrives settled
  /// rather than stopping dead.
  static const Curve panel = Curves.easeOutCubic;

  // ── How long ──────────────────────────────────────────────

  /// A control answering the pointer — a hover lighting, a toolbar appearing
  /// under the cursor. Short enough to read as the control responding rather
  /// than as an animation being played at you.
  static const Duration react = Duration(milliseconds: 90);

  /// A control changing state under your hand: a bar taking focus, a button
  /// filling in, a count changing.
  static const Duration state = Duration(milliseconds: 140);

  /// Something arriving that you did not ask for — a message, a reaction, a
  /// badge. The one place length is worth spending, because it is what makes
  /// an arrival legible instead of a pop. It never blocks anything, so nobody
  /// waits it out.
  static const Duration enter = Duration(milliseconds: 220);

  // ── And how ───────────────────────────────────────────────

  /// Settling into a new state. Fast at the start, easing out, no overshoot.
  static const Curve settle = Curves.easeOut;

  /// Arriving from somewhere. A longer tail than [settle], which is what sells
  /// the movement as travel rather than a fade.
  static const Curve arrive = Curves.easeOutCubic;

  /// A small thing appearing where there was nothing — a reaction chip, an
  /// unread count. Overshoots by a hair and comes back, which reads as *new*
  /// in a way a plain fade does not.
  ///
  /// Only for things that scale up from small. On a slide it reads as a
  /// bounce, and on anything large it reads as a wobble.
  static const Curve pop = Curves.easeOutBack;
}
