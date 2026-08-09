import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_shadows.dart';
import 'widgets/sidebar_content.dart';
import 'widgets/sidebar_tab.dart';

/// The sidebar while it is unpinned: a tab on the left edge that slides the
/// panel out over the content when you click it.
///
/// **Click, not hover.** It used to slide out the moment the pointer touched an
/// invisible 8px strip and retract the moment it left — so it appeared when you
/// were on your way somewhere else, and it disappeared out from under any menu
/// opened inside it, because a context menu is an overlay and the pointer
/// landing on one counted as leaving. Nothing moves now unless it is asked to.
///
/// It closes on a click outside, on Escape, and once you have navigated
/// somewhere: this is a peek at the sidebar, not a second place to live.
class FloatingSidebar extends StatefulWidget {
  /// Extra top padding — pass the title bar height when the appbar is hidden.
  final double topPadding;

  const FloatingSidebar({super.key, this.topPadding = 0});

  @override
  State<FloatingSidebar> createState() => _FloatingSidebarState();
}

class _FloatingSidebarState extends State<FloatingSidebar> {
  /// Held here rather than in AppCubit: a peek is about the next few seconds,
  /// and surviving a restart would be the wrong behaviour for it.
  bool _open = false;

  final FocusNode _focusNode = FocusNode(debugLabel: 'FloatingSidebar');

  /// How much further than its own width the panel is parked off-screen.
  ///
  /// Sliding it to exactly `-width` puts its right edge on x = 0 and hides the
  /// panel — but not its shadow, which is cast with a 50px blur and no
  /// horizontal offset, so it spills back over the content as a smudge down the
  /// left side. Taking the blur off too is what actually hides it.
  static final double _parkedClearance = AppShadows.popover.first.blurRadius;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _openPeek() {
    setState(() => _open = true);
    // So Escape reaches us while it is open.
    _focusNode.requestFocus();
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppCubit>().state;
    final width = SidebarSizing.clamp(
      appState.sidebarWidth,
      windowWidth: MediaQuery.sizeOf(context).width,
    );
    // Mounted even while pinned, so pinning and unpinning can be a transition
    // rather than a widget appearing and disappearing. The tab animates itself
    // out; the panel isn't built at all, since two live copies of the sidebar
    // would be two of every rebuild for something nobody can see.
    final tabVisible = !appState.isPinned && !_open;

    return MultiBlocListener(
      listeners: [
        // Picking a channel, a conversation or a tier ends the peek. Leaving it
        // open would park the panel over the thing you just chose.
        BlocListener<AppCubit, AppState>(
          listenWhen: (a, b) =>
              a.surface != b.surface ||
              a.selectedChannelId != b.selectedChannelId,
          listener: (_, _) => _close(),
        ),
        BlocListener<ChannelChatCubit, ChannelChatState>(
          listenWhen: (a, b) => a.channelId != b.channelId,
          listener: (_, _) => _close(),
        ),
        // Pinning while peeking: the pinned panel is taking over, so this one
        // has nothing left to show.
        BlocListener<AppCubit, AppState>(
          listenWhen: (a, b) => a.isPinned != b.isPinned,
          listener: (_, state) {
            if (state.isPinned) _close();
          },
        ),
      ],
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          focusNode: _focusNode,
          child: Stack(
            children: [
              // Click-away. Below the panel in the stack, so a click on the
              // sidebar itself doesn't dismiss it — and a context menu opened
              // from inside sits in the overlay, above all of this, so using
              // one doesn't either. That was the old version's worst habit.
              if (_open)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _close,
                  ),
                ),

              if (!appState.isPinned)
                AnimatedPositioned(
                  duration: K.sidebarMotion,
                  curve: AppMotion.panel,
                  left: _open ? 0 : -(width + _parkedClearance),
                  top: 0,
                  bottom: 0,
                  width: width,
                  child: AppPanel(
                    shadow: AppShadows.popover,
                    child: SidebarContent(
                      isPinned: false,
                      topPadding: widget.topPadding,
                    ),
                  ),
                ),

              // Slides out through the window edge rather than blinking away,
              // and stays in the tree so it has something to animate from.
              Positioned(
                left: 0,
                top: 12,
                child: IgnorePointer(
                  ignoring: !tabVisible,
                  child: AnimatedSlide(
                    duration: K.sidebarMotion,
                    curve: AppMotion.panel,
                    offset: tabVisible ? Offset.zero : const Offset(-1, 0),
                    child: AnimatedOpacity(
                      duration: K.sidebarMotion,
                      curve: AppMotion.panel,
                      opacity: tabVisible ? 1 : 0,
                      child: SidebarTab(onTap: _openPeek),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
