import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/services/host_platform.dart';
import '../../../../theme/app_motion.dart';
import '../../controls/context_strip.dart';
import '../../controls/control_bar.dart';
import 'participant_grid_layout.dart';
import 'waiting_view.dart';

/// Room is connected — shows participant tiles + control bar.
///
/// Owns the "chrome visible" state that drives focus mode: after a short
/// idle the context strip and control pill fade out together (the strip also
/// collapses), so the video goes edge-to-edge. Any pointer activity brings
/// them back. Combined with an unpinned sidebar (edge handle), this is the
/// full focus-mode payoff.
class RoomView extends StatefulWidget {
  final Room room;

  const RoomView({super.key, required this.room});

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

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  /// Any sign of life in the room area reveals the chrome and resets the idle
  /// timer.
  void _showChrome() {
    if (!_chromeVisible) setState(() => _chromeVisible = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        // Get participants directly from the cubit state
        final participants = livekitState.participants;

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
                      // Context strip fades and collapses with the control
                      // pill so focus mode is truly edge-to-edge.
                      ClipRect(
                        child: AnimatedAlign(
                          alignment: Alignment.topCenter,
                          heightFactor: _chromeVisible ? 1.0 : 0.0,
                          duration: AppMotion.enter,
                          curve: Curves.easeInOut,
                          child: AnimatedOpacity(
                            opacity: _chromeVisible ? 1.0 : 0.0,
                            duration: AppMotion.enter,
                            child: const ContextStrip(),
                          ),
                        ),
                      ),
                      Expanded(
                        child: participants.isEmpty
                            ? const WaitingView()
                            : ParticipantGridLayout(
                                participants: participants,
                                participantSettings:
                                    appState.participantSettings,
                              ),
                      ),
                    ],
                  ),
                  ControlBar(visible: _chromeVisible),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
