import 'package:flutter/material.dart';

import '../../../../../data/classes/role.dart';
import '../../../../common/label_pill.dart';

/// A member's most senior role, beside their name.
///
/// Words rather than icons — a shield and a wrench mean nothing until somebody
/// tells you, and there is room on the row for the letters.
///
/// It shows **one** role, not all of them. A member row is already carrying a
/// name, a presence dot and up to two moderation icons; a list of every role
/// somebody holds belongs in the members dialog, where there is room for it and
/// where somebody has gone looking.
///
/// Uppercased, and cut to [maxChars]. A role's name is whoever made it's to
/// choose and can be anything; a chip that grew with it would push the name it
/// is annotating off the row.
///
/// Eight fits the sidebar, which is the tightest row the chip appears on. The
/// members page has a row several times as wide and is where somebody goes to
/// read roles, so it asks for more — without it the default "Moderator" was
/// ellipsised on the one screen that exists to show roles.
class RoleChip extends StatelessWidget {
  /// What [maxChars] should be anywhere that is not a sidebar row: the
  /// members page, the invite picker — surfaces several times as wide, where
  /// the default silently ellipsised the stock role names.
  static const int wide = 18;

  final Role role;

  /// How much of the name fits here.
  final int maxChars;

  const RoleChip({super.key, required this.role, this.maxChars = 8});

  String get _label {
    final name = role.name.trim().toUpperCase();
    return name.length <= maxChars
        ? name
        : '${name.substring(0, maxChars - 1)}…';
  }

  @override
  Widget build(BuildContext context) {
    // A role that was given no colour is drawn in the neutral fill, rather
    // than being invented one: leaving it uncoloured is a choice somebody made
    // in the editor.
    return LabelPill(label: _label, color: role.displayColor);
  }
}
