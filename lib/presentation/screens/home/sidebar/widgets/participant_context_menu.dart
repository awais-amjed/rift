import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/participant_identity.dart';
import '../../../../../../data/enums/home_surface.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu_region.dart';
import '../../dms/widgets/new_central_dm_dialog.dart';
import '../../../../theme/app_text.dart';

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

  /// Open the server DM with this member.
  ///
  /// The chat key is resolved from the member list rather than assumed: a
  /// voice-channel row only carries an identity and a name, and opening a DM
  /// without the peer's published key fails with a confusing "hasn't enabled
  /// encrypted chat" error even when they have.
  Future<void> _openServerDm(BuildContext context) async {
    final dismiss = ContextMenuScope.of(context);
    final serverCubit = context.read<ServerCubit>();
    final dmCubit = context.read<DmCubit>();
    final centralCubit = context.read<CentralDmCubit>();
    final appCubit = context.read<AppCubit>();
    final userId = ParticipantIdentity.userIdOf(identity);

    dismiss?.call();
    final member = await serverCubit.findMember(userId);

    // Only one DM surface is open at a time.
    centralCubit.closeConversation();
    dmCubit.openConversation(
      peerId: userId,
      peerName: member?.displayName ?? name,
      peerChatKey: member?.chatPublicKey,
    );
    appCubit.setSurface(HomeSurface.serverDms);
  }

  /// Open the central DM search, prefilled with this member's name.
  ///
  /// It can only be a *search*: a central account is a separate identity from a
  /// server membership and nothing links the two, so their server name is a
  /// guess at their handle, not a lookup.
  void _openCentralDm(BuildContext context) {
    ContextMenuScope.of(context)?.call();
    // Central DMs are their own surface now, so switch to it — otherwise the
    // conversation opens behind whatever server pane you were looking at.
    context.read<AppCubit>().setSurface(HomeSurface.centralDms);
    NewCentralDmDialog.show(context, initialQuery: name);
  }

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
                              style: AppText.sectionLabel.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: textQuaternary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              style: AppText.row.copyWith(
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
                      // Messaging — not offered for yourself.
                      if (!isLocal) ...[
                        ContextMenuItem(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Message',
                          onTap: () => _openServerDm(context),
                        ),
                        ContextMenuItem(
                          icon: Icons.public_rounded,
                          label: 'Message on Central',
                          onTap: () => _openCentralDm(context),
                        ),
                        Divider(height: 9, color: borderColor),
                      ],
                      // Mute toggle (local only)
                      ContextMenuItem(
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
                        ContextMenuItem(
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
                        ContextMenuItem(
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
                                    style: AppText.sectionLabel.copyWith(
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
                                    style: AppText.label.copyWith(
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
