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
/// Uppercased, and cut to eight characters. A role's name is whoever made it's
/// to choose and can be anything; a chip that grew with it would push the name
/// it is annotating off the row.
class RoleChip extends StatelessWidget {
  final Role role;
  const RoleChip({super.key, required this.role});

  String get _label {
    final name = role.name.trim().toUpperCase();
    return name.length <= 8 ? name : '${name.substring(0, 7)}…';
  }

  @override
  Widget build(BuildContext context) {
    // A role that was given no colour is drawn in the neutral fill, rather
    // than being invented one: leaving it uncoloured is a choice somebody made
    // in the editor.
    return LabelPill(label: _label, color: role.displayColor);
  }
}
