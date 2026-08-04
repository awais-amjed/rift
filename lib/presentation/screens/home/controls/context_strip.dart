import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/participant_identity.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';

/// Slim strip above the participant grid: channel name, live participant
/// count, and session timer. Keeps chrome to one row so the video area stays
/// as large as possible.
class ContextStrip extends StatefulWidget {
  const ContextStrip({super.key});

  @override
  State<ContextStrip> createState() => _ContextStripState();
}

class _ContextStripState extends State<ContextStrip> {
  late final DateTime _joinedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The strip mounts when the room connects, so "now" is the session start.
    _joinedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final d = DateTime.now().difference(_joinedAt);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<AppCubit, AppState>(
          buildWhen: (prev, curr) =>
              prev.selectedChannelId != curr.selectedChannelId,
          builder: (context, appState) {
            final channelId = appState.selectedChannelId;

            return BlocBuilder<ServerCubit, ServerState>(
              builder: (context, serverState) {
                final channels =
                    serverState.selectedServer?.channels ?? const [];
                final channelName = channels
                    .where((c) => c.id == channelId)
                    .map((c) => c.name)
                    .firstOrNull;

                return BlocBuilder<LiveKitCubit, LiveKitState>(
                  builder: (context, lkState) {
                    // Count distinct users, not raw connections, so a user on
                    // multiple devices (or their screenshare) counts once.
                    final count = lkState.participants
                        .where(
                          (p) => !ParticipantIdentity.isScreenshare(p.identity),
                        )
                        .map((p) => ParticipantIdentity.userIdOf(p.identity))
                        .toSet()
                        .length;

                    return Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Icon(
                            Icons.volume_up_rounded,
                            size: 16,
                            color: themeState.accentBright,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              channelName ?? 'Voice',
                              overflow: TextOverflow.ellipsis,
                              style: AppText.row.copyWith(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: themeState.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '·  $count in voice',
                            style: AppText.secondary.copyWith(
                              color: themeState.textTertiary,
                            ),
                          ),
                          const Spacer(),
                          // Mono and tabular: a timer that ticks must not
                          // change width as the digits roll over.
                          Text(
                            _elapsed,
                            style: AppText.figure.copyWith(
                              fontSize: 11.5,
                              color: themeState.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
