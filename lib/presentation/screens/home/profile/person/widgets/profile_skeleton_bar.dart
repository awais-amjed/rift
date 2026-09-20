import 'package:flutter/material.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/theme_context.dart';

/// A grey bar standing in for one line the roster has not answered with yet.
///
/// Most people you click have never been paged in, so the half-second before
/// [ServerMembersCubit.resolve] returns is the common first frame of this
/// dialog rather than a rare one. Drawing the *shape* of what is coming keeps
/// the dialog the size it will be — a partial fact list that grows two rows
/// under the pointer is worse than a moment of grey, and a spinner where the
/// name goes would blank the one thing the caller could already tell us.
///
/// No shimmer: the wait is short enough that an animation would be a thing
/// starting rather than a thing ending.
class ProfileSkeletonBar extends StatelessWidget {
  /// A fraction of the available width, so the bars come out uneven the way
  /// real answers are.
  final double widthFactor;

  final double height;

  const ProfileSkeletonBar({
    super.key,
    required this.widthFactor,
    this.height = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: context.theme.bgHover,
            borderRadius: BorderRadius.circular(K.radiusPill),
          ),
        ),
      ),
    );
  }
}
