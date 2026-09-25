import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';

/// A small tinted pill stating a fact about the surface you're on —
/// "Encrypted", "Central".
///
/// Tinted from one colour rather than taking separate fill/border/text values,
/// so every chip in the app is the same recipe at a different hue.
///
/// [tooltip] belongs here rather than at each call site because a chip is a
/// *claim*, and a one-word claim is the kind most worth being able to check.
/// "Encrypted" is the product's central promise compressed to nine letters;
/// somebody who does not already know what it covers has nowhere else to ask.
class StatusChip extends StatelessWidget {
  /// What the "Encrypted" chip means, wherever it appears.
  ///
  /// Kept as a constant because two headers show that chip — a channel's and a
  /// DM's — and the encryption claim is the last thing that should say two
  /// slightly different things in two places.
  ///
  /// Leads with *who can read this*, because that is the question the word
  /// "Encrypted" raises and the one a novice actually has. Saying how it works
  /// — sealed on your device, opened on theirs — answers a question nobody
  /// asked and leaves the first one hanging.
  ///
  /// Deliberately about *content*: metadata is visible to the operator
  /// (ARCHITECTURE.md §6), so a tooltip promising more than content would be
  /// the app overstating its own guarantee.
  ///
  /// "in here" rather than "in this channel" because the DM header shows this
  /// chip too, and one sentence that fits both beats two that can drift.
  /// Says the part of "private" that people get wrong. Not "only members can
  /// see it" — that is what the word already means — but that the exception
  /// they would assume exists does not.
  static const String privateTooltip =
      'Only the people in this channel can see it. Server admins are not an '
      'exception: nobody outside holds a key to it.';

  static const String encryptedTooltip =
      'Only the people in here can read these messages. The server stores '
      'them but cannot read them.';

  final IconData icon;
  final String label;
  final Color color;

  /// What the chip's one word actually means. Null for a chip whose label
  /// already says everything it claims.
  final String? tooltip;

  /// What pressing it does, for a chip that leads somewhere — the encryption
  /// chip opens the keys it is making a claim about. Null leaves the chip a
  /// statement, which is what most of them are.
  final VoidCallback? onTap;

  const StatusChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.tooltip,
    this.onTap,
  });

  /// The encryption chip's tooltip once it can be pressed: same claim, plus
  /// the way to check it rather than take it on trust.
  static const String encryptedVerifyTooltip =
      '$encryptedTooltip Click to check the keys.';

  @override
  Widget build(BuildContext context) {
    final press = onTap;
    // Inside the tooltip, not around it: the ink has to be clipped to the
    // pill, and the hand cursor belongs to the thing that answers the click.
    Widget chip = _chip(context);
    if (press != null) {
      chip = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(K.radiusPill),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusPill),
          onTap: press,
          child: chip,
        ),
      );
    }
    final message = tooltip;
    // Look and delay come from `tooltipTheme`, so this matches every other
    // tooltip in the app.
    return message == null ? chip : Tooltip(message: message, child: chip);
  }

  Widget _chip(BuildContext context) {
    // The wash keeps the status colour; the words and the glyph take its
    // ink, which is darker on a light theme so an 11px label still reads.
    final ink = context.theme.statusInk(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(K.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 5,
        children: [
          Icon(icon, size: 11, color: ink),
          // Flexible: a chip states a fact about the surface it sits on, and
          // that surface can be narrow. Better a clipped word than a pill with
          // a striped bar out of its side.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: AppText.chip.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
