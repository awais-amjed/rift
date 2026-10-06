import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/services/participant_roster.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Who is watching the stream with [shareIdentity]: an eye, the count and
/// their faces, in the name badge's glass. Draws nothing while nobody is.
///
/// Read from what each client publishes about itself (`watching`), so it is
/// who has the stream *open*, the same set the join and leave tones are
/// played for — not who LiveKit happens to be sending it to.
class StreamWatchers extends StatelessWidget {
  final String shareIdentity;

  const StreamWatchers({super.key, required this.shareIdentity});

  /// How much of each face the next one covers.
  static const double _overlap = 6;
  static const double _ring = 1.5;

  @override
  Widget build(BuildContext context) {
    // Joined into one string so the tile rebuilds when the set of watchers
    // changes, not on every speaking change: a fresh list never compares
    // equal to the last one.
    final key = context.select<AppCubit, String>(
      (c) => ParticipantRoster.watchersOf(
        c.state.participants,
        shareIdentity,
      ).map((w) => w.userId).join(','),
    );
    if (key.isEmpty) return const SizedBox.shrink();

    final members = context.watch<ServerMembersCubit>().state;
    final roster = context.read<AppCubit>().state.participants;
    final watchers = [
      for (final w in ParticipantRoster.watchersOf(roster, shareIdentity))
        (
          userId: w.userId,
          name: members.nameFor(w.userId, w.name),
          avatar: members.avatarFor(w.userId, null),
        ),
    ];
    final theme = context.theme;
    final shown = watchers.take(K.streamWatchersShown).toList();
    final rest = watchers.length - shown.length;
    const size = K.streamWatcherAvatar;

    return Tooltip(
      message: watchers.map((w) => w.name).join('\n'),
      waitDuration: K.tooltipDelay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 4, 5, 4),
            decoration: BoxDecoration(
              color: theme.bgSecondary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(K.radiusRow),
              border: Border.all(color: theme.borderElevated),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Icon(
                  Icons.visibility_outlined,
                  size: K.iconInline,
                  color: theme.textSecondary,
                ),
                Text(
                  '${watchers.length}',
                  style: AppText.chip.copyWith(color: theme.textSecondary),
                ),
                SizedBox(
                  width: size + (shown.length - 1) * (size - _overlap),
                  height: size,
                  child: Stack(
                    children: [
                      for (final (i, w) in shown.indexed)
                        Positioned(
                          left: i * (size - _overlap),
                          // A ring of the glass between faces, so the one
                          // on top reads as in front rather than merged.
                          child: Container(
                            padding: const EdgeInsets.all(_ring),
                            decoration: BoxDecoration(
                              color: theme.bgSecondary,
                              borderRadius: BorderRadius.circular(
                                size * K.avatarRadiusRatio,
                              ),
                            ),
                            child: UserAvatar(
                              avatarPath: w.avatar,
                              name: w.name,
                              seed: w.userId,
                              size: size - 2 * _ring,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (rest > 0)
                  Text(
                    '+$rest',
                    style: AppText.chip.copyWith(color: theme.textTertiary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
