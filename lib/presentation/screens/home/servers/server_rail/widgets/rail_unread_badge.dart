import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/app_text.dart';

/// The unread count riding on a server chip's corner.
///
/// It carries a ring in the rail's own background colour so it stays legible
/// where it overlaps the avatar beneath it.
class RailUnreadBadge extends StatelessWidget {
  final int count;

  /// Counts above this show as "N+" — past a point the exact number stops
  /// being information and the badge just needs to stay one chip wide.
  static const int max = 99;

  const RailUnreadBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          constraints: const BoxConstraints(minWidth: 16),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: themeState.primary,
            borderRadius: BorderRadius.circular(K.radiusPill),
            border: Border.all(color: themeState.bgSecondary, width: 2),
          ),
          child: Text(
            count > max ? '$max+' : '$count',
            textAlign: TextAlign.center,
            style: AppText.badge.copyWith(color: themeState.onPrimary),
          ),
        );
      },
    );
  }
}
