import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../logic/services/sidebar_sizing.dart';
import '../../../common/app_panel.dart';
import '../../../common/context_menu/context_menu_watcher.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_shadows.dart';
import 'widgets/sidebar_content.dart';
import 'widgets/sidebar_peek_scope.dart';

/// A look at the hidden sidebar without bringing it back: rest the pointer on
/// the middle of the left edge and it slides out over the content, and it
/// slides away again once the pointer has left it.
///
/// It is for glancing at who is in which channel during a call without
/// reflowing the stage. A hover peek existed once and was removed for two
/// habits, which this is built around:
///
/// - **It opened on any touch of the edge.** Only the middle of the edge
///   counts now ([K.sidebarPeekZoneStart]–[K.sidebarPeekZoneEnd]), and only
///   once the pointer has rested there for [K.sidebarPeekDwell] — the corners
///   are where the pointer goes on its way to the rail and the edge tab.
/// - **It vanished from under its own menus.** A context menu is an overlay
///   above the whole app, so reaching for one looked like leaving. It now
///   stays while a menu opened from it ([ContextMenuWatcher]) or a dialog is
///   up, and otherwise waits [K.sidebarPeekLinger] before going.
///
/// A click outside it, Escape, or navigating somewhere ends it at once. The
/// header's chevron keeps it open, which is the docked sidebar coming back.
class SidebarPeek extends StatefulWidget {
  /// The workspace's gutter and title-bar band, so the panel lines up with
  /// where the docked sidebar would sit.
  final EdgeInsets insets;

  /// Passed to the contents, as for the docked sidebar.
  final double topPadding;

  const SidebarPeek({super.key, required this.insets, this.topPadding = 0});

  @override
  State<SidebarPeek> createState() => _SidebarPeekState();
}

class _SidebarPeekState extends State<SidebarPeek> {
  /// Parked this far past its own width, or its shadow — cast with a wide
  /// blur — spills back over the content as a smudge down the left edge.
  static final double _parkedClearance =
      AppShadows.overlayPane.first.blurRadius;

  bool _open = false;

  /// Whether the contents are built. Kept through the closing slide, then
  /// dropped, so a closed peek is not a second sidebar rebuilding for nobody.
  bool _showContent = false;

  /// Whether the pointer is over the panel.
  bool _inside = false;

  /// Menus opened from inside the panel that are still up.
  int _menus = 0;

  Timer? _dwellTimer;
  Timer? _lingerTimer;

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _lingerTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  // ── Opening ──────────────────────────────────────────────

  void _onZoneEnter(PointerEnterEvent event) {
    // A drag passing the edge is going somewhere; it is not a pause.
    if (event.buttons != 0) return;
    _dwellTimer?.cancel();
    _dwellTimer = Timer(K.sidebarPeekDwell, _openPeek);
  }

  void _onZoneExit(PointerExitEvent _) => _dwellTimer?.cancel();

  void _openPeek() {
    if (!mounted || _open) return;
    // Something is on top of the app — a dialog — and the edge underneath it
    // is not what the pointer is resting on.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    setState(() {
      _open = true;
      _showContent = true;
    });
    // A handler rather than a Shortcuts binding: that would need the peek
    // to take focus, and taking it away from the composer to show a panel
    // nobody typed into is its own bug.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  // ── Closing ──────────────────────────────────────────────

  void _close() {
    _lingerTimer?.cancel();
    _dwellTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    if (!_open) return;
    setState(() {
      _open = false;
      _inside = false;
    });
  }

  void _onPanelEnter(PointerEnterEvent _) {
    _inside = true;
    _lingerTimer?.cancel();
  }

  void _onPanelExit(PointerExitEvent _) {
    _inside = false;
    _scheduleClose();
  }

  /// Closes after the linger, unless the pointer came back or something the
  /// peek opened is still up — then it asks again later, because a dialog
  /// closing sends no event here to ask on.
  void _scheduleClose() {
    _lingerTimer?.cancel();
    _lingerTimer = Timer(K.sidebarPeekLinger, () {
      if (!mounted || !_open || _inside) return;
      final covered = !(ModalRoute.of(context)?.isCurrent ?? true);
      if (_menus > 0 || covered) {
        _scheduleClose();
        return;
      }
      _close();
    });
  }

  void _onMenuOpened() => _menus++;

  void _onMenuClosed() {
    if (_menus > 0) _menus--;
    if (_menus == 0 && !_inside) _scheduleClose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    // Escape belongs to whatever is on top: the menu or the dialog first.
    if (_menus > 0 || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    _close();
    return true;
  }

  // ── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sidebarOpen = context.select<AppCubit, bool>(
      (c) => c.state.sidebarOpen,
    );
    final storedWidth = context.select<AppCubit, double>(
      (c) => c.state.sidebarWidth,
    );
    final window = MediaQuery.sizeOf(context);
    final width = SidebarSizing.clamp(storedWidth, windowWidth: window.width);

    return MultiBlocListener(
      listeners: [
        // Picking a channel, a conversation or a tier ends the peek; leaving
        // it open would park it over the thing you just chose. The docked
        // sidebar coming back ends it too — it is taking over.
        BlocListener<AppCubit, AppState>(
          listenWhen: (a, b) =>
              a.surface != b.surface ||
              a.selectedChannelId != b.selectedChannelId ||
              (!a.sidebarOpen && b.sidebarOpen),
          listener: (_, _) => _close(),
        ),
        BlocListener<ChannelChatCubit, ChannelChatState>(
          listenWhen: (a, b) => a.channelId != b.channelId,
          listener: (_, _) => _close(),
        ),
      ],
      child: Stack(
        children: [
          // Click-away. A Listener, not a tap detector: it stays out of the
          // gesture arena, so the click that closes the peek still lands on
          // whatever it was aimed at. Menus and dialogs sit above this in the
          // overlay, so using one never reaches it.
          if (_open)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _close(),
              ),
            ),
          if (!sidebarOpen && !_open)
            Positioned(
              left: 0,
              top: window.height * K.sidebarPeekZoneStart,
              height:
                  window.height *
                  (K.sidebarPeekZoneEnd - K.sidebarPeekZoneStart),
              // The gutter's width: over the canvas that is ground nothing
              // else uses, and a window that isn't maximised has no screen
              // edge to stop the pointer, so a hairline would be hard to hit.
              width: K.panelGutter,
              child: MouseRegion(
                opaque: false,
                onEnter: _onZoneEnter,
                onExit: _onZoneExit,
              ),
            ),
          // The strip between the window edge and the panel is part of the
          // peek. The pointer that opened it is resting there, and without
          // this the panel sliding in past it read as arriving and leaving.
          AnimatedPositioned(
            duration: K.sidebarMotion,
            curve: AppMotion.panel,
            left: _open ? 0 : -(widget.insets.left + width + _parkedClearance),
            top: widget.insets.top,
            bottom: widget.insets.bottom,
            width: widget.insets.left + width,
            onEnd: () {
              if (!_open && _showContent) {
                setState(() => _showContent = false);
              }
            },
            child: !_showContent
                ? const SizedBox.shrink()
                : MouseRegion(
                    onEnter: _onPanelEnter,
                    onExit: _onPanelExit,
                    child: ContextMenuWatcher(
                      onOpened: _onMenuOpened,
                      onClosed: _onMenuClosed,
                      child: SidebarPeekScope(
                        // Follows the gutter as it opens and closes around an
                        // immersive stream, on that animation's clock.
                        child: AnimatedPadding(
                          duration: AppMotion.enter,
                          curve: AppMotion.panel,
                          padding: EdgeInsets.only(left: widget.insets.left),
                          child: AppPanel(
                            width: width,
                            shadow: AppShadows.overlayPane,
                            child: SidebarContent(
                              topPadding: widget.topPadding,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
