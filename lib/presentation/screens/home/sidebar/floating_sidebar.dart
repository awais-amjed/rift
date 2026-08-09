import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
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
    final width = SidebarSizing.clamp(
      context.watch<AppCubit>().state.sidebarWidth,
      windowWidth: MediaQuery.sizeOf(context).width,
    );

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

              AnimatedPositioned(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                left: _open ? 0 : -width,
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

              if (!_open)
                Positioned(
                  left: 0,
                  top: 12,
                  child: SidebarTab(onTap: _openPeek),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
