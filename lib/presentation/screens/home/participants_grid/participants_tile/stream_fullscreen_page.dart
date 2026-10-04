import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/window_fullscreen.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/media_colors.dart';
import 'participant_tile.dart';

/// A watched stream alone on the screen, with the app — sidebar, header, call
/// bar — out of the way and the window itself full screen.
///
/// A page over the whole app rather than a mode of the call screen, so
/// nothing under it has to know: the stage it came from stays where it was
/// and is there again when this goes. Esc, the corner button and the back
/// gesture all leave, and so does the stream ending, which would otherwise
/// leave a black screen with nothing to say why.
class StreamFullscreenPage extends StatefulWidget {
  final Participant participant;
  final bool isMuted;

  const StreamFullscreenPage({
    super.key,
    required this.participant,
    required this.isMuted,
  });

  static Future<void> open(
    BuildContext context, {
    required Participant participant,
    required bool isMuted,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: AppMotion.state,
        reverseTransitionDuration: AppMotion.state,
        pageBuilder: (_, _, _) =>
            StreamFullscreenPage(participant: participant, isMuted: isMuted),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<StreamFullscreenPage> createState() => _StreamFullscreenPageState();
}

class _StreamFullscreenPageState extends State<StreamFullscreenPage> {
  bool _leaving = false;

  String get _identity => widget.participant.identity;

  @override
  void initState() {
    super.initState();
    WindowFullscreen.set(true);
  }

  @override
  void dispose() {
    WindowFullscreen.set(false);
    super.dispose();
  }

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // Stopped from the stream's menu, or the call left.
        BlocListener<LiveKitCubit, LiveKitState>(
          listenWhen: (_, curr) =>
              curr.room == null ||
              !curr.subscribedScreenshares.contains(_identity),
          listener: (_, _) => _leave(),
        ),
        // The sharer stopped or left.
        BlocListener<AppCubit, AppState>(
          listenWhen: (_, curr) =>
              !curr.participants.any((p) => p.identity == _identity),
          listener: (_, _) => _leave(),
        ),
      ],
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _leave},
        child: Focus(
          autofocus: true,
          // A Material, not a bare colour: a page with none under its text
          // draws Flutter's yellow "no Material" underline beneath it.
          child: Material(
            color: MediaColors.videoGround,
            child: ParticipantTileWidget(
              participant: widget.participant,
              isScreenshare: true,
              isMuted: widget.isMuted,
              isExpanded: true,
              isFullscreen: true,
            ),
          ),
        ),
      ),
    );
  }
}
