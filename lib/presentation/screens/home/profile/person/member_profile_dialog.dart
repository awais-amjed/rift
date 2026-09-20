import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/label_pill.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_banned_notice.dart';
import 'widgets/profile_fact.dart';
import 'widgets/profile_local_audio.dart';
import 'widgets/profile_moderation.dart';
import 'widgets/profile_roles.dart';
import 'widgets/profile_section.dart';
import 'widgets/profile_skeleton_bar.dart';

/// Who somebody is on **this server**: their name, their roles, how long they
/// have been here, and the things you can do about them.
///
/// It is a server profile and not a person's, because that is all a server
/// can honestly show. A membership and a central account are separate
/// identities with nothing linking them, and no server knows what other
/// servers exist — so there is no "mutual servers", and [ServerMember.joinedAt]
/// is this server's tenure and says so.
///
/// Opened by id rather than by row, because most of the places you click a
/// person hold only an id: a message's author, a voice tile, a presence entry.
/// The roster is asked for the rest, and until it answers the dialog draws
/// what the caller could tell it.
class MemberProfileDialog extends StatefulWidget {
  final String userId;

  /// What to call them while the roster is still being asked — the name the
  /// clicked row was already showing. Better than a spinner where the name
  /// goes, which would blank the one thing the user could already see.
  final String fallbackName;

  const MemberProfileDialog({
    super.key,
    required this.userId,
    required this.fallbackName,
  });

  @override
  State<MemberProfileDialog> createState() => _MemberProfileDialogState();
}

class _MemberProfileDialogState extends State<MemberProfileDialog> {
  bool _busy = false;

  /// What moderation has changed since the dialog opened.
  ///
  /// The roster refetches on a `users` change, but it arrives over Realtime
  /// and the button has to answer the press now. Held here rather than
  /// emitted, so it goes away with the dialog.
  ServerMember? _moderated;

  @override
  void initState() {
    super.initState();
    // Fills in the member *and* their roles for anybody the roster has not
    // paged in — which is most people, on a server of any size.
    context.read<ServerMembersCubit>().resolve([widget.userId]);
  }

  Future<void> _moderate({bool? muted, bool? deafened, bool? banned}) async {
    final member = _member(context.read<ServerMembersCubit>().state);
    if (member == null) return;
    setState(() => _busy = true);
    final response = await context.read<ServerCubit>().moderateUser(
      userId: member.id,
      isMuted: muted,
      isDeafened: deafened,
      isBanned: banned,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (response.success) {
        _moderated = member.copyWith(
          isMuted: muted,
          isDeafened: deafened,
          isBanned: banned,
        );
      }
    });
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'Could not do that.');
    }
  }

  ServerMember? _member(ServerMembersState state) {
    final known = state.byId[widget.userId];
    final changed = _moderated;
    if (known == null) return changed;
    // The optimistic copy only ever differs in the three moderation flags, so
    // a fresher row wins on everything else.
    return changed == null
        ? known
        : known.copyWith(
            isMuted: changed.isMuted,
            isDeafened: changed.isDeafened,
            isBanned: changed.isBanned,
          );
  }

  /// Open the server DM with them, closing whatever DM surface was open.
  Future<void> _message(ServerMember member) async {
    final dmCubit = context.read<DmCubit>();
    final centralCubit = context.read<CentralDmCubit>();
    final appCubit = context.read<AppCubit>();
    Navigator.of(context).pop();

    // Only one DM surface is open at a time.
    centralCubit.closeConversation();
    await dmCubit.openConversation(
      peerId: member.id,
      peerName: member.displayName,
      peerChatKey: member.chatPublicKey,
    );
    appCubit.setSurface(HomeSurface.serverDms);
  }

  @override
  Widget build(BuildContext context) {
    final membersState = context.watch<ServerMembersCubit>().state;
    final member = _member(membersState);
    final roles = membersState.memberRoles[widget.userId] ?? const [];
    final online = context.watch<ChannelPresenceCubit>().state.isOnline(
      widget.userId,
    );

    final permissions = context.watch<ServerCubit>().state.myPermissions;
    final isAdmin = permissions?.isServerAdmin ?? false;
    final canModerate = isAdmin || (permissions?.isChannelManager ?? false);
    final isMe =
        context.watch<ServerCubit>().state.selectedServer?.user?.id ==
        widget.userId;

    final name = member?.displayName ?? widget.fallbackName;

    return AppModal(
      title: name,
      subtitle: member == null ? null : '@${member.username}',
      titleIcon: ProfileAvatar(
        name: name,
        avatarPath: member?.avatarPath,
        seed: widget.userId,
        isOnline: online,
      ),
      maxWidth: 400,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (member != null) ..._tags(member),
          if (member?.isBanned ?? false) const ProfileBannedNotice(),
          ProfileSection(
            label: 'About',
            spaced: false,
            child: member == null ? _pending : Column(children: _facts(member)),
          ),
          ProfileSection(
            label: 'Roles',
            child: member == null
                ? const ProfileSkeletonBar(widthFactor: 0.34, height: 15)
                : ProfileRoles(roles: roles),
          ),
          // A bot is suppressed here for the same reason as yourself, and
          // not the same one: there is nobody on the other end. It has no
          // ears to turn down, no chat key to seal a DM to, and nothing a
          // server mute would reach.
          if (!isMe && member != null && !member.isBot) ...[
            const SizedBox(height: 18),
            AppButton(
              label: 'Message',
              expanded: true,
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
              // A DM has to be sealed to a key they have published. Without
              // one there is nothing to seal to, so the button says why
              // rather than failing on the press.
              onPressed: member.chatPublicKey == null
                  ? null
                  : () => _message(member),
            ),
            if (member.chatPublicKey == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${member.displayName} has not set up encrypted chat yet.',
                  style: AppText.secondary.copyWith(
                    color: context.theme.textTertiary,
                  ),
                ),
              ),
            ProfileLocalAudio(userId: widget.userId),
            ProfileModeration(
              member: member,
              isBusy: _busy,
              canModerate: canModerate,
              isAdmin: isAdmin,
              onModerate: ({muted, deafened, banned}) =>
                  _moderate(muted: muted, deafened: deafened, banned: banned),
            ),
          ],
        ],
      ),
    );
  }

  /// The pills under the header — only the ones that change what this person
  /// is, never a pill per attribute.
  List<Widget> _tags(ServerMember member) {
    // Only BOT. A ban is a state with a consequence rather than an
    // attribute of the person, and it gets [ProfileBannedNotice] instead —
    // a pill beside this one read as a second kind of thing they are.
    final tags = <Widget>[if (member.isBot) const LabelPill(label: 'BOT')];
    if (tags.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Wrap(spacing: 6, runSpacing: 6, children: tags),
      ),
    ];
  }

  /// The About block while the roster is still being asked — the shape of
  /// what is coming, rather than the one fact the caller happened to know.
  static const Widget _pending = Column(
    children: [
      Padding(
        padding: EdgeInsets.only(bottom: 9),
        child: ProfileSkeletonBar(widthFactor: 0.52),
      ),
      Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: ProfileSkeletonBar(widthFactor: 0.38),
      ),
    ],
  );

  /// No Status row: the dot on the avatar has already answered it, in
  /// colour, an inch above — and this is the shortest fact list in the app
  /// to be spending a third of on something already said.
  List<Widget> _facts(ServerMember? member) {
    final joined = member?.joinedAt;
    return [
      if (joined != null)
        ProfileFact(
          label: 'Member since',
          value: DateFormat('d MMMM y').format(joined.toLocal()),
        ),
      if (member != null && member.isBot && member.manifest.commands.isNotEmpty)
        ProfileFact(
          label: 'Commands',
          value: '${member.manifest.commands.length}',
        ),
      if (member != null)
        ProfileFact(
          label: 'Encrypted chat',
          value: member.chatPublicKey == null ? 'Not set up' : 'Ready',
          quiet: member.chatPublicKey == null,
        ),
    ];
  }
}
