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
import 'stream_view.dart';

/// A watched stream alone on the screen, with the app — sidebars, header,
/// call bar — out of the way: edge to edge in the window as it is, or with
/// the window itself full screen. The corner buttons switch between the two
/// in place, and the one already on leaves.
///
/// A page over the whole app rather than a mode of the call screen, so
/// nothing under it has to know: the stage it came from stays where it was
/// and is there again when this goes. Esc, the corner button and the back
/// gesture all leave, and so does the stream ending, which would otherwise
/// leave a black screen with nothing to say why.
class StreamFullscreenPage extends StatefulWidget {
  final Participant participant;
  final bool isMuted;

  /// The view it opens in: edge to edge or full screen.
  final StreamView view;

  const StreamFullscreenPage({
    super.key,
    required this.participant,
    required this.isMuted,
    required this.view,
  });

  static Future<void> open(
    BuildContext context, {
    required Participant participant,
    required bool isMuted,
    required StreamView view,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: AppMotion.state,
        reverseTransitionDuration: AppMotion.state,
        pageBuilder: (_, _, _) => StreamFullscreenPage(
          participant: participant,
          isMuted: isMuted,
          view: view,
        ),
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
  late StreamView _view = widget.view;

  String get _identity => widget.participant.identity;

  @override
  void initState() {
    super.initState();
    WindowFullscreen.edgeToEdge.value = _view == StreamView.edgeToEdge;
    if (_view == StreamView.fullscreen) WindowFullscreen.set(true);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    WindowFullscreen.edgeToEdge.value = false;
    if (_view == StreamView.fullscreen) WindowFullscreen.set(false);
    super.dispose();
  }

  /// A corner button: the view already on leaves, the other one switches.
  void _show(StreamView next) {
    if (next == _view) {
      _leave();
      return;
    }
    final wasFullscreen = _view == StreamView.fullscreen;
    setState(() => _view = next);
    // Edge to edge first, so the title bar coming back from full screen
    // finds itself hidden rather than flashing up and going again.
    WindowFullscreen.edgeToEdge.value = next == StreamView.edgeToEdge;
    WindowFullscreen.set(!wasFullscreen);
  }

  /// Esc leaves, whatever has the focus. A shortcut bound to this page only
  /// heard it while the page held the focus, and any click takes the focus
  /// away — the app's `KeyboardDismisser` clears it on every tap — so after
  /// one click on the stream Esc did nothing.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    // A dialog or menu opened over the stream gets its own Esc.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    _leave();
    return true;
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
      // A Material, not a bare colour: a page with none under its text
      // draws Flutter's yellow "no Material" underline beneath it.
      child: Material(
        color: MediaColors.videoGround,
        child: ParticipantTileWidget(
          participant: widget.participant,
          isScreenshare: true,
          isMuted: widget.isMuted,
          isExpanded: true,
          view: _view,
          onView: _show,
        ),
      ),
    );
  }
}
