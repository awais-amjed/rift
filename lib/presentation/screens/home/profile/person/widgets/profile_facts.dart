import 'package:flutter/material.dart';

import 'profile_fact.dart';

/// The facts of a profile, side by side until they run out of room.
///
/// A profile holds two or three of these and each is a few words, so a column
/// of them is a column of mostly empty line. Wrapped, they read as one band
/// of information and give the dialog its width back.
class ProfileFacts extends StatelessWidget {
  final List<ProfileFact> facts;

  /// The gap between two facts on the same line. Wide enough that the next
  /// fact's small label is not mistaken for part of this one's answer.
  static const double _gap = 32;

  const ProfileFacts({super.key, required this.facts});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: _gap, runSpacing: 14, children: facts);
  }
}
