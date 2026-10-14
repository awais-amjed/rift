import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/context_menu/context_menu_watcher.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/theme_context.dart';
import '../../controls/call_idle_pill.dart';
import '../../controls/context_strip.dart';
import '../../controls/control_bar.dart';
import '../../soundboard/soundboard_activity.dart';
import 'participant_grid_layout.dart';
import 'waiting_view.dart';

/// Over the widget budget and one job: a connected room, and the focus-mode
/// timing that fades its chrome.
///
/// Room is connected — shows participant tiles + control bar.
///
/// Owns the "chrome visible" state that drives focus mode: after a short
/// idle the context strip and control pill fade out together. Any pointer
/// activity brings them back. Combined with an unpinned sidebar (edge
/// handle), this is the full focus-mode payoff.
///
/// The grid keeps their room whether they show or not, so a hover fades them
/// and moves nothing: room that came and went with them shrank and regrew
/// every tile each time the pointer crossed the stage. A focused cell, and
/// watched streams over a row of everyone else, take the whole stage, and
/// the strip floats over them instead.
class RoomView extends StatefulWidget {
  final Room room;

  /// Inside another pane — see [ParticipantsGrid.embedded]. The shell is
  /// never asked to go full-bleed around it.
  final bool embedded;

  const RoomView({super.key, required this.room, this.embedded = false});

  @override
  State<RoomView> createState() => _RoomViewState();
}

class _RoomViewState extends State<RoomView> {
  /// How long the chrome stays after the last sign of life.
  ///
  /// Longer under a thumb. A cursor keeps the chrome alive just by being
  /// moved, and it is already hovering over the pill when it reaches it; a
  /// thumb has to travel the whole way with nothing keeping the timer fed,
  /// and two seconds is not enough to cross a phone and land on Leave.
  static Duration get _hideDelay => HostPlatform.isMobile
      ? const Duration(seconds: 4)
      : const Duration(seconds: 2);

  bool _chromeVisible = true;
  Timer? _hideTimer;

  /// A menu opened from the bar is up. It sits in the overlay, so the pointer
  /// on it reads as the pointer gone idle, and the bar it hangs from would
  /// fade out from under it.
  bool _menuOpen = false;

  /// Whether one tile fills the stage. The context strip then floats over it
  /// instead of taking a row.
  bool _focused = false;

  /// Read once: [dispose] has to reach it after the context is gone.
  late final AppCubit _appCubit;

  @override
  void initState() {
    super.initState();
    _appCubit = context.read<AppCubit>();
    // A phone's chrome fades on its own: there is no pointer to wait for, and
    // a thumb that wants it back only has to touch the stage.
    //
    // A desktop's waits for the first sign of life. A call is joined by
    // clicking the channel in the sidebar, which leaves the cursor over there
    // — so the timer used to start and finish without the pointer ever
    // entering the stage, and the first thing anybody saw of a call they had
    // just joined was a black rectangle with no channel name, no timer, no
    // microphone and no way to leave.
    if (HostPlatform.isMobile) _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // Leaving the call, or opening a chat over it, must not leave the shell
    // full-bleed around something that is no longer a stream.
    _appCubit.setStageChromeHidden(false);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || _menuOpen) return;
      setState(() => _chromeVisible = false);
      _reportStage();
    });
  }

  /// Any sign of life in the room area reveals the chrome and resets the idle
  /// timer.
  void _showChrome() {
    if (!_chromeVisible) {
      setState(() => _chromeVisible = true);
      _reportStage();
    }
    _scheduleHide();
  }

  /// Tells the shell whether a focused stream is sitting idle, which is when
  /// it may take the whole window. Only in focus: a grid of tiles has gaps of
  /// its own, and running it into the window edge gains nothing.
  void _reportStage() => _appCubit.setStageChromeHidden(
    !widget.embedded && _focused && !_chromeVisible,
  );

  /// The strip, fading with the control pill. Floating over video it needs
  /// the panel's colour behind it, and that fades with it.
  Widget _fadingStrip({Color? background}) => AnimatedOpacity(
    opacity: _chromeVisible ? 1.0 : 0.0,
    duration: AppMotion.enter,
    child: background == null
        ? ContextStrip(embedded: widget.embedded)
        : ColoredBox(
            color: background,
            child: ContextStrip(embedded: widget.embedded),
          ),
  );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        // Get participants directly from the cubit state
        final participants = livekitState.participants;
        // The stage runs under the bars: the strip floats over it.
        final fullStage =
            _focused ||
            ParticipantGridLayout.showsStreamRow(
              participants,
              livekitState.subscribedScreenshares,
            );

        return BlocBuilder<AppCubit, AppState>(
          // The one field this reads. `identical` because the cubit copies the
          // map wholesale on every change, so a shared instance means nobody's
          // local mute or volume moved — and without the test, anything at all
          // in `AppState` rebuilt the whole call surface.
          buildWhen: (previous, current) => !identical(
            previous.participantSettings,
            current.participantSettings,
          ),
          builder: (context, appState) {
            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerHover: (_) => _showChrome(),
              onPointerMove: (_) => _showChrome(),
              // Hover never fires without a mouse, and move only fires during
              // a drag — so on a phone the chrome went away after two seconds
              // and nothing brought it back. That leaves you in a call with no
              // mute and no way out of it but the drawer.
              //
              // A Listener rather than a tap recognizer on purpose: it does
              // not enter the gesture arena, so revealing the controls cannot
              // steal the press that was aimed at one of them.
              onPointerDown: (_) => _showChrome(),
              child: Stack(
                children: [
                  Column(
                    children: [
                      // The strip fades with the control pill and keeps its
                      // row, so the grid under it stays put. Over a full
                      // stage it is drawn on top instead, below.
                      if (!fullStage)
                        IgnorePointer(
                          ignoring: !_chromeVisible,
                          child: _fadingStrip(),
                        ),
                      Expanded(
                        child: participants.isEmpty
                            ? const WaitingView()
                            : ParticipantGridLayout(
                                participants: participants,
                                participantSettings:
                                    appState.participantSettings,
                                // The strip floats over a focused tile.
                                focusTopInset: _chromeVisible
                                    ? ContextStrip.heightFor(
                                        compact: context.layoutMode.isCompact,
                                      )
                                    : 0,
                                // A phone keeps a pill up when the bar goes.
                                controlsInset: _chromeVisible
                                    ? K.callBarClearance
                                    : context.layoutMode.isCompact
                                    ? K.callPillClearance
                                    : 0,
                                stageInset: K.callBarClearance,
                                onFocusChanged: (focused) {
                                  setState(() => _focused = focused);
                                  _reportStage();
                                },
                              ),
                      ),
                    ],
                  ),
                  if (fullStage)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        ignoring: !_chromeVisible,
                        child: _fadingStrip(
                          background: context.theme.bgContent,
                        ),
                      ),
                    ),
                  ContextMenuWatcher(
                    onOpened: () {
                      _menuOpen = true;
                      _showChrome();
                    },
                    onClosed: () {
                      _menuOpen = false;
                      _scheduleHide();
                    },
                    child: ControlBar(visible: _chromeVisible),
                  ),
                  // Above the bar, and outside its IgnorePointer: a clip
                  // that arrives while the chrome has faded is the one
                  // thing on this screen still worth being able to press.
                  SoundboardActivity(visible: _chromeVisible),
                  // A phone hides the bar under a thumb's worth of video, so
                  // the two facts you cannot afford to lose stay behind in a
                  // pill: how long, and whether you are muted.
                  if (context.layoutMode.isCompact)
                    CallIdlePill(visible: !_chromeVisible),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
