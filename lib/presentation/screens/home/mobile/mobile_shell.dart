import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/home_surface.dart';
import '../../../../data/enums/layout_mode.dart';
import '../../../../data/enums/mobile_page.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/services/mobile_page_stack.dart';
import '../../../responsive/shell_scope.dart';
import 'members_sheet.dart';
import 'mobile_home_page.dart';
import 'mobile_page_view.dart';
import 'mobile_shell_scope.dart';
import 'switcher/server_switcher_sheet.dart';

/// The home screen on a phone.
///
/// The list is the screen: a server's channels, or Home's conversations, with
/// the server avatar at the top as the way to anywhere else. Everything a
/// desktop shows in a pane beside the list — a chat, a DM, the call — is a
/// page pushed over it here, one level deep, and back always comes out again.
///
/// **The pages follow the cubits, not the other way round.** Opening a chat is
/// the same `openChannel` call it is on a desktop, from a row, a notification
/// or the quick switcher alike; this watches for it and pushes the page. Going
/// back closes what the page was showing, so the two never disagree about
/// what is open — see [MobilePageStack] for how pages replace and stack.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey();
  MobilePageStack _stack = const MobilePageStack();

  @override
  void initState() {
    super.initState();
    // Whatever was already open when the shell was built — a window narrowed
    // mid-chat, or a notification that opened a conversation during launch.
    //
    // A desktop keeps each surface's conversation open behind the others, so
    // there can be three. Only the one on the surface being shown is the
    // conversation on screen; the rest are closed, because a phone shows one
    // at a time and an invisible open one would swallow the tap that reopens
    // it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppCubit>().state;
      if (app.selectedChannelId != null) _open(MobilePage.call);
      final open = [
        if (context.read<ChannelChatCubit>().state.channelId != null)
          MobilePage.channelChat,
        if (context.read<DmCubit>().state.openPeerId != null)
          MobilePage.serverDm,
        if (context.read<CentralDmCubit>().state.openPeerId != null)
          MobilePage.centralDm,
        if (context.read<CentralDmCubit>().state.friendsOpen)
          MobilePage.friends,
      ];
      for (final page in open) {
        if (_surfaceOf(page) == app.surface) {
          _open(page);
        } else {
          _closeState(page);
        }
      }
    });
  }

  static HomeSurface _surfaceOf(MobilePage page) => switch (page) {
    MobilePage.channelChat || MobilePage.call => HomeSurface.server,
    MobilePage.serverDm => HomeSurface.serverDms,
    MobilePage.centralDm || MobilePage.friends => HomeSurface.centralDms,
  };

  void _open(MobilePage page) => _apply(_stack.opened(page));

  /// Moves to [next], closing the state behind every page it drops.
  ///
  /// Closing is what keeps a page and its cubit in step. A conversation that
  /// is replaced — or backed out of — and left open underneath would be
  /// invisible yet still "open", so tapping the same person again would change
  /// nothing and push nothing.
  void _apply(MobilePageStack next) {
    if (next == _stack) return;
    final dropped = _stack.droppedBy(next);
    setState(() => _stack = next);
    for (final page in dropped) {
      _closeState(page);
    }
  }

  void _closeState(MobilePage page) {
    switch (page) {
      // Leaving the page is not leaving the call. The bar over the list is
      // how you get back, and Leave is the only thing that ends it.
      case MobilePage.call:
        break;
      case MobilePage.channelChat:
        final chat = context.read<ChannelChatCubit>();
        if (chat.state.channelId != null) chat.closeChannel();
      case MobilePage.serverDm:
        final dms = context.read<DmCubit>();
        if (dms.state.openPeerId != null) dms.closeConversation();
      case MobilePage.centralDm:
      case MobilePage.friends:
        final central = context.read<CentralDmCubit>();
        final open = page == MobilePage.friends
            ? central.state.friendsOpen
            : central.state.openPeerId != null;
        if (open) central.closeConversation();
    }
  }

  /// Something other than back closed a page's state — a channel deleted
  /// under you, a call dropped — so the page goes too, without closing again.
  void _closedElsewhere(MobilePage page) {
    if (!_stack.contains(page)) return;
    setState(() => _stack = _stack.closed(page));
  }

  void _openSwitcher() => showServerSwitcherSheet(context);

  void _openMembers() => showMembersSheet(context);

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AppCubit, AppState>(
          listenWhen: (a, b) => a.selectedChannelId != b.selectedChannelId,
          listener: (context, state) {
            if (state.selectedChannelId != null) return _open(MobilePage.call);
            // A DM call clears the channel as it starts: the page stays, it
            // just has a different call on it.
            if (context.read<LiveKitCubit>().state.dmCall != null) return;
            _closedElsewhere(MobilePage.call);
          },
        ),
        // A DM call has no channel to select, so its page follows the call.
        BlocListener<LiveKitCubit, LiveKitState>(
          listenWhen: (a, b) => a.dmCall?.callId != b.dmCall?.callId,
          listener: (_, state) {
            if (state.dmCall != null) return _open(MobilePage.call);
            if (state.currentChannelId == null) {
              _closedElsewhere(MobilePage.call);
            }
          },
        ),
        BlocListener<ChannelChatCubit, ChannelChatState>(
          listenWhen: (a, b) => a.channelId != b.channelId,
          listener: (_, state) => state.channelId != null
              ? _open(MobilePage.channelChat)
              : _closedElsewhere(MobilePage.channelChat),
        ),
        BlocListener<DmCubit, DmState>(
          listenWhen: (a, b) => a.openPeerId != b.openPeerId,
          listener: (_, state) => state.openPeerId != null
              ? _open(MobilePage.serverDm)
              : _closedElsewhere(MobilePage.serverDm),
        ),
        BlocListener<CentralDmCubit, CentralDmState>(
          listenWhen: (a, b) => a.openPeerId != b.openPeerId,
          listener: (_, state) => state.openPeerId != null
              ? _open(MobilePage.centralDm)
              : _closedElsewhere(MobilePage.centralDm),
        ),
        BlocListener<CentralDmCubit, CentralDmState>(
          listenWhen: (a, b) => a.friendsOpen != b.friendsOpen,
          listener: (_, state) => state.friendsOpen
              ? _open(MobilePage.friends)
              : _closedElsewhere(MobilePage.friends),
        ),
      ],
      child: ShellScope(
        mode: LayoutMode.compact,
        sidebarOpen: false,
        membersOpen: false,
        toggleSidebar: _openSwitcher,
        toggleMembers: _openMembers,
        dismissOverlays: () {},
        child: MobileShellScope(
          openCall: () => _open(MobilePage.call),
          callOnTop: _stack.top == MobilePage.call,
          // The system back gesture reaches the root navigator first; this
          // hands it to the shell's own while it has a page to take off.
          child: NavigatorPopHandler(
            onPopWithResult: (_) => _navigator.currentState?.maybePop(),
            child: Navigator(
              key: _navigator,
              pages: [
                const MaterialPage(
                  key: ValueKey('home'),
                  child: MobileHomePage(),
                ),
                for (final page in _stack.pages)
                  MaterialPage(
                    key: ValueKey(page),
                    child: MobilePageView(page: page),
                  ),
              ],
              onDidRemovePage: (removed) {
                final key = removed.key;
                if (key is ValueKey<MobilePage>) {
                  _apply(_stack.closed(key.value));
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
