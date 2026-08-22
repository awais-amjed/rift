import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
import '../../../data/enums/auth_status.dart';
import '../../../data/enums/layout_mode.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../logic/cubits/dm/dm_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../../logic/services/host_platform.dart';
import '../../common/app_modal.dart';
import '../../common/canvas_backdrop.dart';
import '../../common/overlay_scrim.dart';
import '../../responsive/shell_scope.dart';
import 'main_content/main_content.dart';
import 'servers/add_server/add_server_dialog.dart';
import 'members_sidebar/members_sidebar.dart';
import 'sidebar/sidebar.dart';
import 'sidebar/widgets/sidebar_tab.dart';
import 'sidebar/widgets/sidebar_header.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _titleBarHeight = K.titleBarHeight;

  /// Whether each pane is showing *while overlaid*.
  ///
  /// Deliberately not the hydrated `AppCubit` flags. A drawer has to start
  /// closed however the app was left, and dragging a window narrow for a
  /// moment must not overwrite a docking preference chosen for a wide one —
  /// so the two states are kept apart and [ShellScope] picks between them.
  bool _sidebarOverlayOpen = false;
  bool _membersOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStartup());
  }

  Future<void> _onStartup() async {
    if (!mounted) return;

    final vaultCubit = context.read<VaultCubit>();

    // Wait for checkVaultStatus() to settle before using state.masterSeed —
    // if we proceed while status is still unknown, loginToServer() silently
    // fails and the stale token is used until the next cold start.
    if (vaultCubit.state.status == AuthStatus.unknown) {
      await vaultCubit.stream
          .firstWhere((s) => s.status != AuthStatus.unknown)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => vaultCubit.state,
          );
      if (!mounted) return;
    }

    final serverState = context.read<ServerCubit>().state;

    if (serverState.servers.isEmpty) {
      _openAddServer();
    } else {
      // Re-authenticate the active server; other servers authenticate lazily.
      await context.read<ServerCubit>().loginSelectedServer();
    }
  }

  /// Opening one drawer closes the other: they overlap, and two at once on a
  /// phone would leave nothing of the content between them.
  void _toggleSidebar(LayoutMode mode) {
    if (!mode.sidebarIsOverlay) {
      context.read<AppCubit>().toggleSidebar();
      return;
    }
    setState(() {
      _sidebarOverlayOpen = !_sidebarOverlayOpen;
      if (_sidebarOverlayOpen) _membersOverlayOpen = false;
    });
  }

  void _toggleMembers(LayoutMode mode) {
    if (!mode.membersIsOverlay) {
      context.read<AppCubit>().toggleMembersSidebar();
      return;
    }
    setState(() {
      _membersOverlayOpen = !_membersOverlayOpen;
      if (_membersOverlayOpen) _sidebarOverlayOpen = false;
    });
  }

  /// Gets whatever is overlaid out of the way, leaving docked panes alone.
  void _dismissOverlays() {
    if (!_sidebarOverlayOpen && !_membersOverlayOpen) return;
    setState(() {
      _sidebarOverlayOpen = false;
      _membersOverlayOpen = false;
    });
  }

  /// No servers — on a first run, or after leaving the last one. Straight to
  /// join-or-create: there is nothing to select from.
  void _openAddServer() {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<VaultCubit>()),
        ],
        child: const AddServerDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ServerCubit, ServerState>(
          listenWhen: (prev, curr) =>
              prev.servers.length != curr.servers.length,
          listener: (context, state) {
            if (state.servers.isEmpty) _openAddServer();
          },
        ),
        // Navigating is what a drawer is *for*, so it closes once you have
        // used it. Without this you pick a channel and it stays sitting on top
        // of the thing you picked, which on a phone is the whole window.
        // Every route in is covered: switching server, opening a text or voice
        // channel, and opening either kind of DM.
        BlocListener<ServerCubit, ServerState>(
          listenWhen: (prev, curr) =>
              prev.selectedServerId != curr.selectedServerId,
          listener: (context, _) => _dismissOverlays(),
        ),
        BlocListener<AppCubit, AppState>(
          listenWhen: (prev, curr) =>
              prev.selectedChannelId != curr.selectedChannelId ||
              prev.surface != curr.surface,
          listener: (context, _) => _dismissOverlays(),
        ),
        BlocListener<ChannelChatCubit, ChannelChatState>(
          listenWhen: (prev, curr) => prev.channelId != curr.channelId,
          listener: (context, _) => _dismissOverlays(),
        ),
        BlocListener<CentralDmCubit, CentralDmState>(
          listenWhen: (prev, curr) => prev.openPeerId != curr.openPeerId,
          listener: (context, _) => _dismissOverlays(),
        ),
        BlocListener<DmCubit, DmState>(
          listenWhen: (prev, curr) => prev.openPeerId != curr.openPeerId,
          listener: (context, _) => _dismissOverlays(),
        ),
      ],
      child: Scaffold(
        body: BlocBuilder<AppCubit, AppState>(
          // Showing and hiding the sidebar no longer restructures this screen
          // — the sidebar and its tab each animate themselves — so the only
          // thing left that moves the workspace is the title bar.
          buildWhen: (prev, curr) =>
              prev.titleBarVisible != curr.titleBarVisible ||
              prev.sidebarOpen != curr.sidebarOpen ||
              prev.membersSidebarOpen != curr.membersSidebarOpen,
          builder: (context, appState) {
            final mode = context.layoutMode;
            final titleBarVisible = appState.titleBarVisible;
            final chrome = HostPlatform.drawsOwnWindowChrome;
            final topPadding = !chrome
                ? 0.0
                : (titleBarVisible ? 0.0 : K.titleBarHiddenSidebarPadding);
            return ShellScope(
              mode: mode,
              sidebarOpen: mode.sidebarIsOverlay
                  ? _sidebarOverlayOpen
                  : appState.sidebarOpen,
              membersOpen: mode.membersIsOverlay
                  ? _membersOverlayOpen
                  : appState.membersSidebarOpen,
              toggleSidebar: () => _toggleSidebar(mode),
              toggleMembers: () => _toggleMembers(mode),
              dismissOverlays: _dismissOverlays,
              child: PopScope(
                // Back closes the drawer before it closes anything else. A
                // drawer is a layer over this screen, and on a phone the
                // system back gesture is how a layer is dismissed — without
                // this it skips straight past the open drawer and leaves the
                // app, which is the single most jarring thing a drawer can do.
                canPop: !_sidebarOverlayOpen && !_membersOverlayOpen,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) _dismissOverlays();
                },
                child: _QuickSwitcherShortcut(
                  child: CanvasBackdrop(
                    child: Padding(
                      // The gutter that makes the panels islands, and which a
                      // phone does not get — the panels are the screen there,
                      // and each holds its own content clear of the display's
                      // cutouts. The title bar is painted above the whole app,
                      // so the workspace steps out from under it; the gutter
                      // takes over when it's hidden.
                      padding: EdgeInsets.only(
                        top: !chrome
                            ? mode.panelGutter
                            : (titleBarVisible
                                  ? _titleBarHeight
                                  : K.panelGutter),
                        left: mode.panelGutter,
                        right: mode.panelGutter,
                        bottom: mode.panelGutter,
                      ),
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              // Docked, the sidebar takes its width out of the
                              // row. Overlaid it is mounted further down this
                              // stack instead, so the content runs full width
                              // underneath it rather than beside it.
                              if (!mode.sidebarIsOverlay)
                                Sidebar(
                                  open: appState.sidebarOpen,
                                  topPadding: topPadding,
                                ),
                              const Expanded(child: MainContent()),
                            ],
                          ),
                          // One scrim for both drawers — only ever one is open.
                          OverlayScrim(
                            visible: _sidebarOverlayOpen || _membersOverlayOpen,
                            onDismiss: _dismissOverlays,
                          ),
                          if (mode.sidebarIsOverlay)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Sidebar(
                                open: _sidebarOverlayOpen,
                                topPadding: topPadding,
                                floating: true,
                              ),
                            ),
                          if (mode.membersIsOverlay)
                            Align(
                              alignment: Alignment.centerRight,
                              child: MembersSidebar(
                                open: _membersOverlayOpen,
                                floating: true,
                              ),
                            ),
                          // There is deliberately no swipe-in-from-the-edge to
                          // *open* a drawer. Both screen edges belong to
                          // Android's back gesture, and an app that also
                          // claims them wins the race only sometimes — tried
                          // here, and the swipe left the app instead. Getting
                          // out of that would mean carving a gesture exclusion
                          // out of the OS's own navigation for one shortcut.
                          // The header button opens a drawer; back and the
                          // scrim close it, and the scrim takes a fling as
                          // well as a tap, because by then it owns the middle
                          // of the screen rather than its edge.
                          //
                          // The edge tabs are the way back to a *docked* pane. On
                          // a phone the same job is done by the buttons in the
                          // chat header, where a thumb can reach them.
                          if (!mode.isCompact)
                            const Positioned(
                              top: 12,
                              left: 0,
                              child: SidebarTab(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Binds Ctrl/⌘+K to the quick switcher across the whole home screen.
///
/// Both modifiers are bound on every platform rather than branching: a user
/// coming from a Mac will reach for ⌘ on Linux, and nothing else in the app
/// claims either combination.
class _QuickSwitcherShortcut extends StatelessWidget {
  final Widget child;

  const _QuickSwitcherShortcut({required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            openQuickSwitcher(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            openQuickSwitcher(context),
      },
      child: child,
    );
  }
}
