import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/enums/home_surface.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../data/participant_identity.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../common/member_avatar.dart';
import '../../../../theme/theme_context.dart';
import '../../profile/person/show_person_profile.dart';
import 'participant_admin_section.dart';
import 'participant_bot_section.dart';
import 'participant_volume_control.dart';

/// Over the widget budget and one job: what you can do to one participant, and
/// each item decides for itself whether to show.
///
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

  /// Open their profile. The menu is the one way in: a click on the row is
  /// left alone, so pressing someone in a call never throws a dialog over it.
  ///
  /// Dismissed first and opened in the same frame — the menu's context is
  /// still mounted until the next build, which is all the dialog needs to
  /// find its navigator and cubits.
  void _openProfile(BuildContext context) {
    ContextMenuScope.of(context)?.call();
    showMemberProfile(
      context,
      userId: ParticipantIdentity.userIdOf(identity),
      name: name,
    );
  }

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
    await dmCubit.openConversation(
      peerId: userId,
      peerName: member?.displayName ?? name,
      peerChatKey: member?.chatPublicKey,
    );
    appCubit.setSurface(HomeSurface.serverDms);
  }

  /// Open the friends page with the add-friend field prefilled with this
  /// member's name.
  ///
  /// It can only ever be a *guess*: a central account is a separate identity
  /// from a server membership and nothing links the two, so their server name
  /// is a suggestion at their handle rather than a lookup. It arrives selected
  /// so that typing over it is one keystroke.
  ///
  /// It used to seed a search, and picking a name from the results messaged
  /// them. There is no messaging a stranger on central now — the most this can
  /// do is offer to ask.
  void _openCentralDm(BuildContext context) {
    ContextMenuScope.of(context)?.call();
    // Central DMs are their own surface now, so switch to it — otherwise the
    // friends page opens behind whatever server pane you were looking at.
    context.read<AppCubit>().setSurface(HomeSurface.centralDms);
    // Seeds the add-friend field, which focuses itself in response.
    context.read<CentralDmCubit>().setHandleQuery(name);
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final borderColor = themeState.borderPrimary;

    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        // For local participant, use the LiveKit mic state
        final liveKitState = context.watch<LiveKitCubit>().state;
        final serverState = context.watch<ServerCubit>().state;
        final permissions = serverState.myPermissions;
        final isServerAdmin = permissions?.isServerAdmin ?? false;
        final isModerator =
            (permissions?.isChannelManager ?? false) || isServerAdmin;

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

        // An admin is not a moderation target for another admin — the
        // server says so, and the menu should agree rather than offering
        // a button that comes back "cannot_moderate_admin". Unknown
        // resolves to false on purpose: the member list may not have
        // loaded yet, and hiding the controls from everyone until it does
        // would be the worse failure.
        final targetIsAdmin =
            context
                .watch<ServerMembersCubit>()
                .state
                .byId[targetUserId]
                ?.permissions
                .isServerAdmin ??
            false;

        // A bot is a member here and nowhere else. Two items below cannot
        // mean anything for one, and one of them is worse than useless:
        // "Add on Central" seeds the add-friend field with a name, and a
        // bot's name on central is a stranger who happens to share it.
        final targetIsBot =
            context
                .watch<ServerMembersCubit>()
                .state
                .byId[targetUserId]
                ?.isBot ??
            false;

        // Which call they're in, if any: ours when they're on the roster,
        // otherwise whatever presence says. Only "Move to" needs it — and
        // only to leave out the channel they're already in.
        final voiceChannelId = isLive
            ? liveKitState.currentChannelId
            : context.watch<ChannelPresenceCubit>().state.channelOf(
                targetUserId,
              );

        final soundboardMuted =
            appState
                .participantSettings[ParticipantIdentity.soundboardSettingsKey(
                  targetUserId,
                )]
                ?.muted ??
            false;

        final bool isMuted;
        final double volume;

        if (isLocal) {
          isMuted = !liveKitState.isMicOn;
          volume = 1.0; // Volume slider not applicable for self
        } else {
          final setting = appState.participantSettings[targetUserId];
          isMuted = setting?.muted ?? false;
          volume = setting?.volume ?? 1.0;
        }

        return ContextMenuPanel(
          heading: isLocal ? 'You' : (isLive ? 'Participant' : 'Member'),
          subheading: name,
          leading: MemberAvatar(userId: targetUserId, name: name, size: 24),
          children: [
            Divider(height: 1, color: borderColor),
            const SizedBox(height: 4),
            ContextMenuItem(
              icon: Icons.person_outline_rounded,
              label: 'View profile',
              onTap: () => _openProfile(context),
            ),
            if (isLocal) Divider(height: 9, color: borderColor),
            // Messaging — not offered for yourself.
            if (!isLocal) ...[
              ContextMenuItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Message',
                onTap: () => _openServerDm(context),
              ),
              if (!targetIsBot)
                ContextMenuItem(
                  icon: Icons.public_rounded,
                  label: 'Add on Rift',
                  onTap: () => _openCentralDm(context),
                ),
              Divider(height: 9, color: borderColor),
            ],
            // Volume above the mutes: how loud they are, then whether
            // you hear them at all.
            if (!isLocal)
              ParticipantVolumeControl(
                target: identity,
                isMuted: isMuted,
                volume: volume,
              ),
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
            // Their soundboard, separately. A clip is played by this
            // device, so this switches off nothing for anybody else —
            // and it leaves their voice alone, which is the reason it is
            // not the mute above. A bot has no soundboard to turn down.
            if (!isLocal && !targetIsBot)
              ContextMenuItem(
                icon: soundboardMuted
                    ? Icons.graphic_eq_rounded
                    : Icons.graphic_eq_outlined,
                label: soundboardMuted
                    ? 'Unmute their soundboard'
                    : 'Mute their soundboard',
                isDangerous: soundboardMuted,
                onTap: () => context.read<AppCubit>().setSoundboardMutedFor(
                  targetUserId,
                  !soundboardMuted,
                ),
              ),
            // Sending a summoned bot away — not moderation, and not
            // behind the same permission. Above the admin section because
            // for a bot it is the only item on here anybody usually wants.
            if (!isLocal)
              ParticipantBotSection(
                targetUserId: targetUserId,
                voiceChannelId: voiceChannelId,
                name: name,
              ),
            // Moderation and roles, each behind its own permission.
            if (!isLocal)
              ParticipantAdminSection(
                target: identity,
                targetUserId: targetUserId,
                isModerator: isModerator,
                name: name,
                isServerAdmin: isServerAdmin,
                // `KICK_MEMBERS`, which a role can hold without managing
                // channels. Never a bot, which `kick_member` refuses.
                canKick:
                    (permissions?.can(ServerPermission.kickMembers) ?? false) &&
                    !targetIsBot,
                isLive: isLive,
                voiceChannelId: voiceChannelId,
                targetIsAdmin: targetIsAdmin,
                isServerMuted: isServerMuted,
                isServerDeafened: isServerDeafened,
              ),
            const SizedBox(height: 2),
          ],
        );
      },
    );
  }
}
