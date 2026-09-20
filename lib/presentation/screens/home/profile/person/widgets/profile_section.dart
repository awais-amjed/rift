import 'package:flutter/material.dart';

import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One labelled block in a profile — "Roles", "Your audio", "Moderation".
///
/// The label is what makes a profile readable as a set of answers rather than
/// a pile of controls: the audio slider and the server-mute button look alike
/// and do very different things, and the only thing that says which is yours
/// alone is the word above it.
class ProfileSection extends StatelessWidget {
  final String label;
  final Widget child;

  /// Space above, for every section but the first.
  final bool spaced;

  const ProfileSection({
    super.key,
    required this.label,
    required this.child,
    this.spaced = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: spaced ? 18 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppText.sectionLabel.copyWith(
              color: context.theme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
