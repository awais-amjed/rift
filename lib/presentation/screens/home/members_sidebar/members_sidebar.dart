import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/member_roster.dart';
import '../channels/channel_list/widgets/section_header.dart';
import 'widgets/member_row.dart';

/// The right-hand member list for the selected server — everyone who has
/// joined, split into online and offline.
///
/// Membership comes from `list_users` (fetched once per server, and again when
/// the server changes); *presence* comes from the Realtime presence channel, so
/// the online split updates live without refetching the roster.
class MembersSidebar extends StatefulWidget {
  const MembersSidebar({super.key});

  @override
  State<MembersSidebar> createState() => _MembersSidebarState();
}

class _MembersSidebarState extends State<MembersSidebar> {
  /// Matches ChatHeader's bar height so the two align across the top.
  static const double _headerHeight = 46;

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
                  ? K.membersSidebarWidth
                  : K.membersSidebarCollapsedWidth,
              decoration: BoxDecoration(
                // Same surface as the left sidebar — this is the other edge of
                // the same chrome, not part of the content area.
                color: themeState.sidebarBg,
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
    // Mirrors ChatHeader's bar so the two line up across the top.
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.only(left: 14, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.people_alt_rounded,
            size: 16,
            color: themeState.textQuaternary,
          ),
          const SizedBox(width: 8),
          Text(
            'Members',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: themeState.textPrimary,
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
      const SizedBox(height: 14),
      SectionHeader(label: '$label — ${members.length}'),
      const SizedBox(height: 4),
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
