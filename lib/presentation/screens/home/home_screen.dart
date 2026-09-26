import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
import '../../../data/enums/layout_mode.dart';
import '../../../data/invite_link.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../logic/cubits/dm/dm_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../../logic/services/host_platform.dart';
import '../../../logic/services/invite_link_listener.dart';
import '../../common/app_modal.dart';
import '../../common/canvas_backdrop.dart';
import '../../common/overlay_scrim.dart';
import '../../responsive/shell_scope.dart';
import '../../theme/app_motion.dart';
import 'main_content/main_content.dart';
import 'main_content/widgets/voice_connection_listener.dart';
import 'members_sidebar/members_sidebar.dart';
import 'mobile/mobile_shell.dart';
import 'servers/add_server/add_server_dialog.dart';
import 'sidebar/sidebar.dart';
import 'sidebar/sidebar_peek.dart';
import 'sidebar/widgets/sidebar_header.dart';

/// Over the widget budget and one job: the home screen, on a phone and on a
/// desktop. Most of it is the desktop row of panes and the overlays that open
/// over it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _titleBarHeight = K.titleBarHeight;

  /// Whether the member list is showing *while overlaid*.
  ///
  /// Deliberately not the hydrated `AppCubit` flag. A drawer has to start
  /// closed however the app was left, and dragging a window narrower for a
  /// moment must not overwrite a docking preference chosen for a wide one —
  /// so the two states are kept apart and [ShellScope] picks between them.
  bool _membersOverlayOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStartup());
  }

  Future<void> _onStartup() async {
    if (!mounted) return;

    await context.read<VaultCubit>().settled();
    if (!mounted) return;

    final serverState = context.read<ServerCubit>().state;

    if (serverState.servers.isEmpty) {
      _openAddServer();
    } else {
      // Re-authenticate the active server; other servers authenticate lazily.
      await context.read<ServerCubit>().loginSelectedServer();
    }

    // After the vault has settled, not before: joining needs a signed-in
    // account, and a link that arrived at launch is held until something is
    // listening rather than dropped.
    if (!mounted) return;
    await InviteLinkListener.instance.start(_onInvite);
  }

  @override
  void dispose() {
    InviteLinkListener.instance.detach();
    super.dispose();
  }

  /// An invite tapped outside the app.
  ///
  /// Straight into the join step with the link in hand. Rebuilt into its
  /// canonical form rather than passed through: the link may have arrived
  /// wrapped in `rift://join#…`, and the join step wants an invite, not the
  /// envelope it came in.
  void _onInvite(InviteLink invite) {
    if (!mounted) return;
    _openAddServer(
      inviteLink: InviteLink.build(invite.serverUrl, invite.inviteCode),
    );
  }

  /// The member list's own toggle. Overlaid — a medium window — it is a
  /// drawer with throwaway state; docked it is a saved preference.
  void _toggleMembers(LayoutMode mode) {
    if (!mode.membersIsOverlay) {
      context.read<AppCubit>().toggleMembersSidebar();
      return;
    }
    setState(() => _membersOverlayOpen = !_membersOverlayOpen);
  }

  /// Gets the overlaid member list out of the way, leaving a docked one alone.
  void _dismissOverlays() {
    if (!_membersOverlayOpen) return;
    setState(() => _membersOverlayOpen = false);
  }

  /// Whether an [AddServerDialog] is currently up, and which one.
  ///
  /// A first run with no servers opens one, and an invite arriving moments
  /// later opens another — so two stacked, the join popped the top, and the
  /// new member's first sight of the app was an offer to add the server they
  /// had just joined. The counter is what makes replacing one safe: the
  /// outgoing dialog's `whenComplete` runs after the incoming one is already
  /// registered, and without it that late callback would clear the flag for a
  /// dialog still on screen.
  bool _addServerOpen = false;
  int _addServerGeneration = 0;

  /// No servers — on a first run, or after leaving the last one. Straight to
  /// join-or-create: there is nothing to select from.
  void _openAddServer({String? inviteLink}) {
    if (_addServerOpen) Navigator.of(context).pop();

    final generation = ++_addServerGeneration;
    _addServerOpen = true;

    showCustomDialog(
      context: context,
      build: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<VaultCubit>()),
        ],
        child: AddServerDialog(inviteLink: inviteLink),
      ),
    ).whenComplete(() {
      if (generation == _addServerGeneration) _addServerOpen = false;
    });
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
          listenWhen: (prev, curr) =>
              prev.openPeerId != curr.openPeerId ||
              prev.friendsOpen != curr.friendsOpen,
          listener: (context, _) => _dismissOverlays(),
        ),
        BlocListener<DmCubit, DmState>(
          listenWhen: (prev, curr) => prev.openPeerId != curr.openPeerId,
          listener: (context, _) => _dismissOverlays(),
        ),
      ],
      child: Scaffold(
        body: VoiceConnectionListener(
          // A phone is a different shell, not a squeezed desktop: the list is
          // the screen and everything else is pushed over it.
          child: context.layoutMode.isCompact
              ? _QuickSwitcherShortcut(child: _buildPhone())
              : _QuickSwitcherShortcut(child: _buildDesktop(context)),
        ),
      ),
    );
  }

  /// The phone shell — also what a desktop window narrowed to a phone's width
  /// gets, which has the app's own title bar painted over its top edge to
  /// step out from under.
  Widget _buildPhone() {
    if (!HostPlatform.drawsOwnWindowChrome) return const MobileShell();
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) => a.titleBarVisible != b.titleBarVisible,
      builder: (context, appState) => Padding(
        padding: EdgeInsets.only(
          top: appState.titleBarVisible ? _titleBarHeight : 0,
        ),
        child: const MobileShell(),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      // Showing and hiding the sidebar no longer restructures this screen —
      // the sidebar and its tab each animate themselves — so the only thing
      // left that moves the workspace is the title bar.
      buildWhen: (prev, curr) =>
          prev.titleBarVisible != curr.titleBarVisible ||
          prev.sidebarOpen != curr.sidebarOpen ||
          prev.membersSidebarShown != curr.membersSidebarShown ||
          prev.stageChromeHidden != curr.stageChromeHidden,
      builder: (context, appState) {
        final mode = context.layoutMode;
        final titleBarVisible = appState.titleBarVisible;
        final chrome = HostPlatform.drawsOwnWindowChrome;
        final topPadding = !chrome
            ? 0.0
            : (titleBarVisible ? 0.0 : K.titleBarHiddenSidebarPadding);
        final membersOpen = mode.membersIsOverlay
            ? _membersOverlayOpen
            : appState.membersSidebarShown;
        final immersive =
            appState.stageChromeHidden && !appState.sidebarOpen && !membersOpen;
        // The gutter goes with the chrome; the title bar's band stays, since
        // that is the window's own and is hidden on its own switch.
        final gutter = immersive ? 0.0 : K.panelGutter;
        // The gutter that makes the panels islands. The title bar is painted
        // above the whole app, so the workspace steps out from under it; the
        // gutter takes over when it's hidden.
        final insets = EdgeInsets.only(
          top: !chrome ? gutter : (titleBarVisible ? _titleBarHeight : gutter),
          left: gutter,
          right: gutter,
          bottom: gutter,
        );
        return ShellScope(
          mode: mode,
          sidebarOpen: appState.sidebarOpen,
          membersOpen: membersOpen,
          immersive: immersive,
          toggleSidebar: context.read<AppCubit>().toggleSidebar,
          toggleMembers: () => _toggleMembers(mode),
          dismissOverlays: _dismissOverlays,
          child: PopScope(
            // Back closes the drawer before it closes anything else — a drawer
            // is a layer over this screen, and back is how a layer goes away.
            canPop: !_membersOverlayOpen,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _dismissOverlays();
            },
            child: CanvasBackdrop(
              child: Stack(
                children: [
                  AnimatedPadding(
                    // Same length and curve as the content panel's corners, so
                    // the two read as one movement.
                    duration: AppMotion.enter,
                    curve: AppMotion.panel,
                    padding: insets,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            Sidebar(
                              open: appState.sidebarOpen,
                              topPadding: topPadding,
                            ),
                            const Expanded(child: MainContent()),
                          ],
                        ),
                        OverlayScrim(
                          visible: _membersOverlayOpen,
                          onDismiss: _dismissOverlays,
                        ),
                        if (mode.membersIsOverlay)
                          Align(
                            alignment: Alignment.centerRight,
                            child: MembersSidebar(
                              open: _membersOverlayOpen,
                              floating: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Outside the gutter, so its hot zone is the window's own
                  // edge rather than the workspace's.
                  Positioned.fill(
                    child: SidebarPeek(insets: insets, topPadding: topPadding),
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
