import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
import '../../../common/loading_dots.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../chat/widgets/chat_header.dart';
import '../sidebar/widgets/sidebar_resize_handle.dart';
import 'widgets/members_sidebar_list.dart';

/// The right-hand member list for the selected server — everyone who has
/// joined, split into online and offline.
///
/// Both halves are live. Membership comes from [ServerMembersCubit], which
/// refetches whenever a `users` row changes, so someone joining on an invite
/// appears without a reselect; *presence* comes from the Realtime presence
/// channel and decides which group they land in.
///
/// [open] is passed in rather than read from [AppCubit] because where this is
/// mounted decides what openness means — a saved preference while docked, and
/// throwaway drawer state while overlaid. See `ShellScope`.
///
/// Docked, it is resizable the way the left sidebar is: the gutter between it
/// and the content is the grab strip, the width is stored raw in [AppState]
/// and clamped on read by [MembersSidebarSizing], and a double-click puts it
/// back. Floating, it is a drawer at its default width.
class MembersSidebar extends StatefulWidget {
  /// Whether the panel is showing. Animating, not mounting: see below.
  final bool open;

  /// Floating above the content rather than sitting beside it. Takes a shadow,
  /// and keeps a gutter on both sides instead of only the one facing the chat.
  final bool floating;

  const MembersSidebar({super.key, required this.open, this.floating = false});

  @override
  State<MembersSidebar> createState() => _MembersSidebarState();
}

class _MembersSidebarState extends State<MembersSidebar> {
  /// Matches ChatHeader's bar height so the two align across the top.
  static const double _headerHeight = ChatHeader.height;

  /// The width while a drag is in progress; null otherwise.
  double? _dragWidth;

  /// The panel and the gutter that separates it from the content, which has to
  /// go with it — a 10px gap left hanging off the right of the window is the
  /// tell that something used to be there. Floating, there is content on both
  /// sides of it, so it takes a gutter on both — and on a phone there are no
  /// gutters at all, so it is just the panel. Docked, the gutter on the
  /// content side is the resize handle, which is the same width.
  double _fullWidth(double width, double gutter) =>
      widget.floating ? width + gutter * 2 : width + K.sidebarResizeHandleWidth;

  /// The pointer moves left to widen a panel on the right, so the delta is
  /// subtracted.
  void _onDrag(double delta, double stored, double windowWidth) {
    setState(() {
      _dragWidth = MembersSidebarSizing.clamp(
        (_dragWidth ?? stored) - delta,
        windowWidth: windowWidth,
      );
    });
  }

  void _onDragEnd() {
    final width = _dragWidth;
    if (width != null) context.read<AppCubit>().setMembersSidebarWidth(width);
    setState(() => _dragWidth = null);
  }

  void _reset() {
    setState(() => _dragWidth = null);
    context.read<AppCubit>().setMembersSidebarWidth(K.membersSidebarWidth);
  }

  /// Whether the contents are built. Dropped once a close has finished, and
  /// seeded from the launch state, because starting closed runs no animation
  /// and so would never reach the `onEnd` that drops them.
  late bool _showContent;

  @override
  void initState() {
    super.initState();
    _showContent = widget.open;
  }

  @override
  void didUpdateWidget(MembersSidebar old) {
    super.didUpdateWidget(old);
    // Back before the opening animation runs, or the panel would widen around
    // nothing.
    if (widget.open && !_showContent) {
      setState(() => _showContent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) =>
          a.participantSettings != b.participantSettings ||
          a.membersSidebarWidth != b.membersSidebarWidth,
      builder: (context, appState) {
        final mode = context.layoutMode;
        final gutter = mode.panelGutter;
        final windowWidth = MediaQuery.sizeOf(context).width;
        // Floating, the drawer keeps its default width: it is covering
        // the content, and a width dragged for sitting beside it does
        // not carry over.
        final width = widget.floating
            ? K.membersSidebarWidth
            : MembersSidebarSizing.clamp(
                _dragWidth ?? appState.membersSidebarWidth,
                windowWidth: windowWidth,
              );
        final fullWidth = _fullWidth(width, gutter);
        return AnimatedContainer(
          // A drag tracks the pointer exactly; see the left sidebar.
          duration: _dragWidth != null ? Duration.zero : K.sidebarMotion,
          curve: AppMotion.panel,
          width: widget.open ? fullWidth : 0,
          onEnd: () {
            if (!widget.open && _showContent) {
              setState(() => _showContent = false);
            }
          },
          // The width animates but `open` flips at once, so without the
          // clip the full-width content spends the whole animation being
          // laid out at a few pixels — a row of overflow errors every
          // toggle. Pin the child to its real width and clip instead: it
          // slides out through the right edge rather than being squeezed.
          child: !_showContent
              ? const SizedBox.shrink()
              : ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: fullWidth,
                    maxWidth: fullWidth,
                    child: Row(
                      children: [
                        if (widget.floating)
                          SizedBox(width: gutter)
                        else
                          SidebarResizeHandle(
                            onDrag: (delta) => _onDrag(
                              delta,
                              appState.membersSidebarWidth,
                              windowWidth,
                            ),
                            onDragEnd: _onDragEnd,
                            onReset: _reset,
                          ),
                        SizedBox(
                          width: width,
                          // A panel in its own right — the same chrome as
                          // the left sidebar, floating beside the content
                          // rather than bordering it.
                          child: AppPanel(
                            shadow: widget.floating
                                ? AppShadows.overlayPane
                                : null,
                            // Mirrors the left drawer: square against the
                            // screen edge, rounded on the content side.
                            borderRadius:
                                widget.floating && !mode.panelsAreIslands
                                ? const BorderRadius.horizontal(
                                    left: Radius.circular(K.radiusCard),
                                  )
                                : null,
                            child: _buildList(context, themeState, appState),
                          ),
                        ),
                        if (widget.floating) SizedBox(width: gutter),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildList(
    BuildContext context,
    ThemeState themeState,
    AppState appState,
  ) {
    final myId = context.watch<ServerCubit>().state.selectedServer?.user?.id;
    final presence = context.watch<ChannelPresenceCubit>().state;
    final roster = context.watch<ServerMembersCubit>().state;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The server's own count, not the length of what has been paged in.
        _header(
          context,
          themeState,
          roster.loaded ? roster.peopleCount + roster.bots.length : null,
        ),
        Expanded(
          child: !roster.loaded
              ? Center(
                  child: roster.loading
                      ? LoadingDots(
                          color: context.theme.accentBright,
                          dotSize: 4,
                        )
                      : const SizedBox.shrink(),
                )
              : MembersSidebarList(
                  appState: appState,
                  roster: roster,
                  onlineIds: presence.onlineUserIds,
                  myId: myId,
                  onLoadMore: () => unawaited(
                    context.read<ServerMembersCubit>().loadMorePeople(),
                  ),
                ),
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
              style: AppText.strong.copyWith(color: themeState.textPrimary),
            ),
          ),
          // Mono, so the tally sits still while people come and go.
          if (count != null)
            Text(
              '$count',
              style: AppText.figure.copyWith(color: themeState.textTertiary),
            ),
          // Through the shell rather than straight to AppCubit: overlaid,
          // this is the drawer's own close button and has to shut the drawer,
          // not quietly rewrite the docking preference for wider windows.
          IconButton(
            tooltip: 'Hide members',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: themeState.textQuaternary,
            ),
            onPressed: ShellScope.of(context).toggleMembers,
          ),
        ],
      ),
    );
  }
}
