import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/member_roster.dart';
import '../../../common/app_panel.dart';
import '../../../theme/app_text.dart';
import '../channels/channel_list/widgets/section_header.dart';
import '../chat/widgets/chat_header.dart';
import 'widgets/member_row.dart';

/// The right-hand member list for the selected server — everyone who has
/// joined, split into online and offline.
///
/// Both halves are live. Membership comes from [ServerMembersCubit], which
/// refetches whenever a `users` row changes, so someone joining on an invite
/// appears without a reselect; *presence* comes from the Realtime presence
/// channel and decides which group they land in.
class MembersSidebar extends StatelessWidget {
  /// Matches ChatHeader's bar height so the two align across the top.
  static const double _headerHeight = ChatHeader.height;

  const MembersSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<AppCubit, AppState>(
          buildWhen: (a, b) =>
              a.membersSidebarOpen != b.membersSidebarOpen ||
              a.participantSettings != b.participantSettings,
          builder: (context, appState) {
            final open = appState.membersSidebarOpen;
            final targetWidth = open
                ? K.membersSidebarWidth
                : K.membersSidebarCollapsedWidth;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: targetWidth,
              // A panel in its own right — same chrome surface as the left
              // sidebar, floating beside the content rather than bordering it.
              child: AppPanel(
                // The width animates but `open` flips at once, so without this
                // the full-width content spends the whole animation being laid
                // out at 42px — a row of overflow errors every toggle. Pin the
                // child to its destination width and clip instead: it slides
                // behind the edge rather than being squeezed.
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: targetWidth,
                    maxWidth: targetWidth,
                    child: open
                        ? _buildList(context, themeState, appState)
                        : _buildCollapsed(context, themeState),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Collapsed: a narrow strip whose only job is to get the panel back.
  Widget _buildCollapsed(BuildContext context, ThemeState themeState) {
    return Column(
      children: [
        // Same height as the header bar, so the button lines up with the chat
        // header across the top instead of floating.
        SizedBox(
          height: _headerHeight,
          child: Center(
            child: IconButton(
              tooltip: 'Show members',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Icons.people_alt_rounded,
                size: 18,
                color: themeState.textTertiary,
              ),
              onPressed: () => context.read<AppCubit>().toggleMembersSidebar(),
            ),
          ),
        ),
        Divider(height: 1, color: themeState.borderPrimary),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    ThemeState themeState,
    AppState appState,
  ) {
    final myId = context
        .watch<ServerCubit>()
        .state
        .selectedServer
        ?.user
        ?.id;
    final presence = context.watch<ChannelPresenceCubit>().state;
    final roster = context.watch<ServerMembersCubit>().state;
    final members = roster.members;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context, themeState, members?.length),
        Expanded(
          child: members == null
              ? Center(
                  child: roster.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const SizedBox.shrink(),
                )
              : _roster(themeState, appState, members, presence, myId),
        ),
      ],
    );
  }

  Widget _header(BuildContext context, ThemeState themeState, int? count) {
    // Mirrors ChatHeader's bar so the two line up across the top.
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Expanded(
            child: Text(
              'Members',
              style: AppText.row.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: themeState.textPrimary,
              ),
            ),
          ),
          // Mono, so the tally sits still while people come and go.
          if (count != null)
            Text(
              '$count',
              style: AppText.figure.copyWith(
                fontSize: 10,
                color: themeState.textQuaternary,
              ),
            ),
          IconButton(
            tooltip: 'Hide members',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: themeState.textQuaternary,
            ),
            onPressed: () => context.read<AppCubit>().toggleMembersSidebar(),
          ),
        ],
      ),
    );
  }

  Widget _roster(
    ThemeState themeState,
    AppState appState,
    List<ServerMember> members,
    ChannelPresenceState presence,
    String? myId,
  ) {
    final split = MemberRoster.split(members, presence.onlineUserIds);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        ..._group(
          themeState,
          appState,
          label: 'Online',
          members: split.online,
          isOnline: true,
          myId: myId,
        ),
        ..._group(
          themeState,
          appState,
          label: 'Offline',
          members: split.offline,
          isOnline: false,
          myId: myId,
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  /// One presence group: the shared [SectionHeader] plus its rows. Empty groups
  /// render nothing rather than a lone "Offline — 0".
  List<Widget> _group(
    ThemeState themeState,
    AppState appState, {
    required String label,
    required List<ServerMember> members,
    required bool isOnline,
    required String? myId,
  }) {
    if (members.isEmpty) return const [];
    return [
      SectionHeader(label: '$label — ${members.length}'),
      for (final member in members)
        MemberRow(
          member: member,
          themeState: themeState,
          isOnline: isOnline,
          isMe: member.id == myId,
          setting: appState.participantSettings[member.id],
        ),
    ];
  }
}
