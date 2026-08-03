import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/participant_identity.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';

/// Dialog-based context menu for a participant — mute toggle + volume slider.
///
/// [identity] is a live LiveKit identity when the target is in your voice
/// channel, or a bare **user id** when they aren't (a member of another voice
/// channel, listed from Realtime presence). Local mute and volume are stored
/// per user and re-applied on their next join, so they work either way.
///
/// Server-side moderation is offered only for a live participant: its current
/// state arrives through LiveKit participant metadata, so for anyone else the
/// menu would have to show a guess. Moderating an absent member is still
/// possible from the Members dialog, which reads the real state.
class ParticipantContextMenu extends StatelessWidget {
  final String identity;
  final String name;
  final bool isLocal;

  const ParticipantContextMenu({
    super.key,
    required this.identity,
    required this.name,
    this.isLocal = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final bgColor = themeState.bgElevated;
        final borderColor = themeState.borderPrimary;
        final textPrimary = themeState.textPrimary;
        final textSecondary = themeState.textSecondary;
        final textQuaternary = themeState.textQuaternary;

        return BlocBuilder<AppCubit, AppState>(
          builder: (context, appState) {
            // For local participant, use the LiveKit mic state
            final liveKitState = context.watch<LiveKitCubit>().state;
            final serverState = context.watch<ServerCubit>().state;
            final permissions = serverState.selectedServer?.user?.permissions;
            final isModerator =
                (permissions?.isChannelManager ?? false) ||
                (permissions?.isServerAdmin ?? false);

            // Server-side moderation state of the target (from LiveKit
            // participant metadata), matched by user id so a screenshare or
            // multi-device identity still resolves to the right person.
            final targetUserId = ParticipantIdentity.userIdOf(identity);
            final targetInfo = appState.participants
                .where((p) => p.userId == targetUserId)
                .firstOrNull;
            final isServerMuted = targetInfo?.isServerMuted ?? false;
            final isServerDeafened = targetInfo?.isServerDeafened ?? false;
            // Absent from the roster → not in a voice channel with us, so
            // their moderation state is unknown here.
            final isLive = targetInfo != null;

            final bool isMuted;
            final double volume;

            if (isLocal) {
              isMuted = !liveKitState.isMicEnabled;
              volume = 1.0; // Volume slider not applicable for self
            } else {
              final setting = appState.participantSettings[targetUserId];
              isMuted = setting?.muted ?? false;
              volume = setting?.volume ?? 1.0;
            }

            return Container(
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 224),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isLocal
                                  ? 'YOU'
                                  : (isLive ? 'PARTICIPANT' : 'MEMBER'),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: textQuaternary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: borderColor),
                      const SizedBox(height: 4),
                      // Mute toggle (local only)
                      _MenuItem(
                        icon: isMuted ? Icons.mic_off : Icons.mic,
                        label: isMuted ? 'Unmute' : 'Mute',
                        isDangerous: isMuted,
                        onTap: () {
                          if (isLocal) {
                            context.read<LiveKitCubit>().toggleMicrophone();
                          } else {
                            context.read<LiveKitCubit>().setParticipantMute(
                              identity,
                              !isMuted,
                            );
                          }
                        },
                      ),
                      // Server-side moderation (moderators only, remote
                      // participants only). Persists across rejoins.
                      if (!isLocal && isLive && isModerator) ...[
                        _MenuItem(
                          icon: isServerMuted ? Icons.mic : Icons.mic_off,
                          label: isServerMuted
                              ? 'Server unmute'
                              : 'Server mute',
                          isDangerous: !isServerMuted,
                          onTap: () {
                            context.read<LiveKitCubit>().moderateParticipant(
                              participantIdentity: identity,
                              muted: !isServerMuted,
                            );
                          },
                        ),
                        _MenuItem(
                          icon: isServerDeafened
                              ? Icons.headset
                              : Icons.headset_off,
                          label: isServerDeafened
                              ? 'Server undeafen'
                              : 'Server deafen',
                          isDangerous: !isServerDeafened,
                          onTap: () {
                            context.read<LiveKitCubit>().moderateParticipant(
                              participantIdentity: identity,
                              deafened: !isServerDeafened,
                            );
                          },
                        ),
                      ],
                      // Volume slider (only for remote participants)
                      if (!isLocal) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'VOLUME',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      color: textQuaternary,
                                    ),
                                  ),
                                  Text(
                                    isMuted
                                        ? '—'
                                        : '${(volume * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                  activeTrackColor: themeState.primary,
                                  inactiveTrackColor: themeState.bgActive,
                                  thumbColor: themeState.primary,
                                ),
                                child: Slider(
                                  value: isMuted ? 0 : volume,
                                  min: 0,
                                  max: 1,
                                  onChanged: isMuted
                                      ? null
                                      : (v) {
                                          context
                                              .read<LiveKitCubit>()
                                              .setParticipantVolume(
                                                identity,
                                                v,
                                              );
                                        },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDangerous;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    this.isDangerous = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final color = isDangerous
            ? CustomColors.error
            : themeState.textSecondary;
        final bgColor = isDangerous
            ? CustomColors.error.withValues(alpha: 0.1)
            : Colors.transparent;

        return Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            hoverColor: themeState.bgHover,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
