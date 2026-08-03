import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/member_roster.dart';
import 'widgets/member_group.dart';
import 'widgets/member_row.dart';

/// The right-hand member list for the selected server — everyone who has
/// joined, split into online and offline.
///
/// Membership comes from `list_users` (fetched once per server, and again when
/// the server changes); *presence* comes from the Realtime presence channel, so
/// the online split updates live without refetching the roster.
class MembersSidebar extends StatefulWidget {
  static const double width = 210;
  static const double collapsedWidth = 40;

  const MembersSidebar({super.key});

  @override
  State<MembersSidebar> createState() => _MembersSidebarState();
}

class _MembersSidebarState extends State<MembersSidebar> {
  List<ServerMember>? _members;
  String? _loadedServerId;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  Future<void> _loadIfNeeded() async {
    final serverId = context.read<ServerCubit>().state.selectedServer?.id;
    if (serverId == null || serverId == _loadedServerId || _loading) return;
    setState(() => _loading = true);
    final result = await context.read<ServerCubit>().listMembers();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success) {
        _members = result.members;
        _loadedServerId = serverId;
      }
    });
  }

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
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: open
                  ? MembersSidebar.width
                  : MembersSidebar.collapsedWidth,
              decoration: BoxDecoration(
                color: themeState.bgPrimary,
                border: Border(
                  left: BorderSide(color: themeState.borderPrimary),
                ),
              ),
              child: open
                  ? _buildList(themeState, appState)
                  : _buildCollapsed(themeState),
            );
          },
        );
      },
    );
  }

  /// Collapsed: a narrow strip whose only job is to get the panel back.
  Widget _buildCollapsed(ThemeState themeState) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: IconButton(
          tooltip: 'Show members',
          icon: Icon(
            Icons.people_alt_outlined,
            size: 18,
            color: themeState.textTertiary,
          ),
          onPressed: () => context.read<AppCubit>().toggleMembersSidebar(),
        ),
      ),
    );
  }

  Widget _buildList(ThemeState themeState, AppState appState) {
    // A server switch happens under us without initState running again.
    _loadIfNeeded();

    return BlocBuilder<ServerCubit, ServerState>(
      buildWhen: (a, b) => a.selectedServer?.id != b.selectedServer?.id,
      builder: (context, serverState) {
        final myId = serverState.selectedServer?.user?.id;
        return BlocBuilder<ChannelPresenceCubit, ChannelPresenceState>(
          builder: (context, presence) {
            final members = _members;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(themeState),
                Expanded(
                  child: members == null
                      ? Center(
                          child: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        )
                      : _roster(themeState, appState, members, presence, myId),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _header(ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 2),
      child: Row(
        children: [
          Text(
            'MEMBERS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: themeState.textQuaternary,
            ),
          ),
          const Spacer(),
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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      children: [
        if (split.online.isNotEmpty) ...[
          MemberGroupHeader(
            label: 'ONLINE',
            count: split.online.length,
            themeState: themeState,
          ),
          for (final member in split.online)
            MemberRow(
              member: member,
              themeState: themeState,
              isOnline: true,
              isMe: member.id == myId,
              setting: appState.participantSettings[member.id],
            ),
        ],
        if (split.offline.isNotEmpty) ...[
          MemberGroupHeader(
            label: 'OFFLINE',
            count: split.offline.length,
            themeState: themeState,
          ),
          for (final member in split.offline)
            MemberRow(
              member: member,
              themeState: themeState,
              isOnline: false,
              isMe: member.id == myId,
              setting: appState.participantSettings[member.id],
            ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
