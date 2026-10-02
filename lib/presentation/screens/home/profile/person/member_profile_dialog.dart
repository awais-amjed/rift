import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../data/classes/server.dart';
import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../data/enums/server_permission.dart';
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
import '../../../../common/modal_columns.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'verification/profile_verification.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_banned_notice.dart';
import 'widgets/profile_fact.dart';
import 'widgets/profile_facts.dart';
import 'widgets/profile_local_audio.dart';
import 'widgets/profile_moderation.dart';
import 'widgets/profile_roles.dart';
import 'widgets/profile_safety_actions.dart';
import 'widgets/profile_section.dart';
import 'widgets/profile_skeleton_bar.dart';

/// Over the widget budget and one job: a member's server profile and what you
/// can do about them.
///
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
          // A ban either way settles a kick (`moderate_user`).
          isKicked: banned == null ? null : false,
        );
      }
    });
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'Could not do that.');
    }
  }

  Future<void> _kick() async {
    final member = _member(context.read<ServerMembersCubit>().state);
    if (member == null) return;
    setState(() => _busy = true);
    final response = await context.read<ServerCubit>().kickMember(
      userId: member.id,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (response.success) {
        _moderated = member.copyWith(isBanned: true, isKicked: true);
      }
    });
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'Could not do that.');
    }
  }

  /// Time them out, or lift it with [Duration.zero].
  Future<void> _timeOut(Duration duration) async {
    final member = _member(context.read<ServerMembersCubit>().state);
    if (member == null) return;
    setState(() => _busy = true);
    final response = await context.read<ServerCubit>().timeOutMember(
      targetId: member.id,
      duration: duration,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (response.success) {
        final until = DateTime.tryParse('${response.data}')?.toLocal();
        _moderated = member.copyWith(
          timedOutUntil: until,
          clearTimedOut: until == null,
        );
      }
    });
    if (!response.success) {
      HelperMethods.showError(
        error: switch (response.errorCode) {
          'cannot_moderate_peer' =>
            'Someone who can time others out can\'t be timed out.',
          'cannot_moderate_admin' => 'Admins can\'t be timed out.',
          _ => response.error ?? 'Could not do that.',
        },
      );
    }
  }

  ServerMember? _member(ServerMembersState state) {
    final known = state.byId[widget.userId];
    final changed = _moderated;
    if (known == null) return changed;
    // The optimistic copy only ever differs in the moderation state, so a
    // fresher row wins on everything else.
    return changed == null
        ? known
        : known.copyWith(
            isMuted: changed.isMuted,
            isDeafened: changed.isDeafened,
            isBanned: changed.isBanned,
            isKicked: changed.isKicked,
            timedOutUntil: changed.timedOutUntil,
            clearTimedOut: changed.timedOutUntil == null,
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

    final serverState = context.watch<ServerCubit>().state;
    final server = serverState.selectedServer;
    final permissions = serverState.myPermissions;
    final isAdmin = permissions?.isServerAdmin ?? false;
    final canModerate = isAdmin || (permissions?.isChannelManager ?? false);
    final canTimeOut = permissions?.can(ServerPermission.muteMembers) ?? false;
    final canKick = permissions?.can(ServerPermission.kickMembers) ?? false;
    final canBan = permissions?.can(ServerPermission.banMembers) ?? false;
    final isMe = server?.user?.id == widget.userId;

    final name = member?.displayName ?? widget.fallbackName;
    final actions = _actions(member, isMe);

    return AppModal(
      title: name,
      subtitle: member == null ? null : '@${member.username}',
      titleIcon: ProfileAvatar(
        name: name,
        avatarPath: member?.avatarPath,
        seed: widget.userId,
        isOnline: online,
      ),
      maxWidth: K.profileWidth,
      sheetOnPhone: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (member != null) ..._tags(member),
          if (member?.isBanned ?? false)
            ProfileBannedNotice(kicked: member!.isKicked),
          // Who they are on the left, what you can do about them on the
          // right — and stacked in that order on anything too narrow, which
          // is the order the dialog had when it was one column.
          ModalColumns(
            minColumnWidth: _columnWidth,
            children: [
              _identity(member, roles, server, isMe),
              // Left out rather than empty: stacked, `ModalColumns` rules
              // between its children, and a second column with nothing in it
              // drew a hairline under the profile with nothing after it.
              ?actions,
            ],
          ),
          if (member != null && !isMe && !member.isBot)
            ProfileModeration(
              member: member,
              isBusy: _busy,
              canModerate: canModerate,
              isAdmin: isAdmin,
              canTimeOut: canTimeOut,
              canKick: canKick,
              canBan: canBan,
              onModerate: ({muted, deafened, banned}) =>
                  _moderate(muted: muted, deafened: deafened, banned: banned),
              onKick: _kick,
              onTimeOut: _timeOut,
            ),
        ],
      ),
    );
  }

  /// The narrowest a profile column may be before the two stack. Lower than
  /// `ModalColumns`' own default: these hold facts and switches rather than
  /// form fields, and they read fine well before 300.
  static const double _columnWidth = 260;

  /// Who they are: the facts, then their roles.
  Widget _identity(
    ServerMember? member,
    List<Role> roles,
    Server? server,
    bool isMe,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ProfileSection(
          label: 'About',
          spaced: false,
          child: member == null
              ? _pending
              : ProfileFacts(facts: _facts(member)),
        ),
        ProfileSection(
          label: 'Roles',
          child: member == null
              ? const ProfileSkeletonBar(widthFactor: 0.34, height: 15)
              : ProfileRoles(roles: roles),
        ),
        // Never for yourself or a bot: your own key is not somebody else's to
        // check, and a safety number is compared out of band with a person who
        // can read it back to you — a bot has a chat key and nobody to say it.
        if (member != null && !isMe && !member.isBot && server != null)
          ProfileVerification(
            tier: 'server',
            personId: member.id,
            personName: member.displayName,
            theirChatKey: member.chatPublicKey,
            myId: server.user?.id ?? '',
            host: Uri.parse(server.supabaseUrl).host,
          ),
      ],
    );
  }

  /// What you can do about them — nothing at all for yourself.
  ///
  /// A bot gets the one action that means something: **Message**. A DM to a
  /// bot is a real conversation, sealed between the two of you and unreadable
  /// by the server (BOTS.md §3), and a bot publishes a chat key like anybody
  /// else — this dialog used to say it held none and suppress the button on
  /// that basis, which left a capability the database allows and the bot SDK
  /// implements with no way into it from the app at all.
  ///
  /// What a bot does not get is the rest: there is nobody on the other end to
  /// turn down, and nothing a server mute would reach.
  Widget? _actions(ServerMember? member, bool isMe) {
    if (member == null || isMe) return null;
    if (member.isBot) {
      // Wrapped, and not decoration: this column is laid out beside the
      // about panel, so a lone `expanded` button stretches to the height of
      // whatever is taller. `min` keeps it button-sized.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: 'Message',
            expanded: true,
            icon: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: K.iconRow,
            ),
            onPressed: member.chatPublicKey == null
                ? null
                : () => _message(member),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppButton(
          label: 'Message',
          expanded: true,
          icon: const Icon(Icons.chat_bubble_outline_rounded, size: K.iconRow),
          // A DM has to be sealed to a key they have published. Without one
          // there is nothing to seal to, so the button says why rather than
          // failing on the press.
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
        ProfileSafetyActions(member: member),
        ProfileLocalAudio(userId: widget.userId),
      ],
    );
  }

  /// The pills under the header — only the ones that change what this person
  /// is, never a pill per attribute.
  List<Widget> _tags(ServerMember member) {
    // Only BOT. A ban is a state with a consequence rather than an
    // attribute of the person, and it gets [ProfileBannedNotice] instead —
    // a pill beside this one read as a second kind of thing they are.
    final tags = <Widget>[if (member.isBot) const LabelPill(label: 'Bot')];
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
  List<ProfileFact> _facts(ServerMember? member) {
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
