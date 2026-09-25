import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../data/participant_identity.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/services/call_duration.dart';
import '../../../common/status_chip.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';
import '../profile/person/verification/show_channel_encryption.dart';
import 'phone_context_strip.dart';

/// Slim strip above the participant grid: channel name, live participant
/// count, and session timer. Keeps chrome to one row so the video area stays
/// as large as possible.
class ContextStrip extends StatefulWidget {
  const ContextStrip({super.key});

  /// How tall the strip is; a phone's is taller for its back button.
  static double heightFor({required bool compact}) =>
      compact ? K.paneHeaderHeight + 8 : K.paneHeaderHeight;

  @override
  State<ContextStrip> createState() => _ContextStripState();
}

class _ContextStripState extends State<ContextStrip> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (prev, curr) =>
          prev.selectedChannelId != curr.selectedChannelId,
      builder: (context, appState) {
        final channelId = appState.selectedChannelId;

        return BlocBuilder<ServerCubit, ServerState>(
          builder: (context, serverState) {
            final channels = serverState.selectedServer?.channels ?? const [];
            final channelName = channels
                .where((c) => c.id == channelId)
                .map((c) => c.name)
                .firstOrNull;

            return BlocBuilder<LiveKitCubit, LiveKitState>(
              builder: (context, lkState) {
                // Count distinct users, not raw connections, so a user on
                // multiple devices (or sharing a screen or a track)
                // counts once.
                final count = lkState.participants
                    .where((p) => !ParticipantIdentity.isShare(p.identity))
                    .map((p) => ParticipantIdentity.userIdOf(p.identity))
                    .toSet()
                    .length;

                final elapsed = Text(
                  formatCallDuration(
                    DateTime.now().difference(
                      lkState.connectedAt ?? DateTime.now(),
                    ),
                  ),
                  // Mono and tabular: a timer that ticks must not change
                  // width as the digits roll over.
                  style: AppText.figure.copyWith(
                    color: themeState.textTertiary,
                  ),
                );
                if (context.layoutMode.isCompact) {
                  return PhoneContextStrip(
                    channelName: channelName ?? 'Voice',
                    serverName: serverState.selectedServer?.name,
                    elapsed: elapsed,
                  );
                }
                return Container(
                  height: ContextStrip.heightFor(compact: false),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: themeState.borderPrimary),
                    ),
                  ),
                  child: Row(
                    children: [
                      // One flexible group, so the timer sits hard against
                      // the right edge. A `Flexible` name beside a
                      // `Spacer` splits the free space with it, leaving
                      // whatever the name doesn't use stranded past the
                      // timer and parking it mid-strip.
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.volume_up_rounded,
                              size: K.iconRow,
                              color: themeState.accentBright,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                channelName ?? 'Voice',
                                overflow: TextOverflow.ellipsis,
                                style: AppText.panelTitle.copyWith(
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
                          ],
                        ),
                      ),
                      // The same claim the chat header makes, in the surface
                      // where the keys are doing the work — and pressable
                      // for the same reason: a claim you cannot check is
                      // one you have to take on trust.
                      StatusChip(
                        icon: Icons.lock_outline,
                        label: 'Encrypted',
                        color: CustomColors.success,
                        tooltip: StatusChip.encryptedVerifyTooltip,
                        onTap: () => showCallEncryption(
                          context,
                          channelName: channelName ?? 'Voice',
                          participants: context
                              .read<AppCubit>()
                              .state
                              .participants,
                        ),
                      ),
                      const SizedBox(width: 12),
                      elapsed,
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
