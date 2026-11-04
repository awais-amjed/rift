import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/clean_picture_gate.dart';
import '../../../../../logic/services/video_stats_sampler.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/theme_context.dart';

/// A remote video, covered until its picture is clean — see
/// [CleanPictureGate]. Without it, starting to watch a stream showed about a
/// second of garbage.
///
/// The renderer stays mounted under the cover: adaptive stream pauses a track
/// nothing is drawing, and a paused track never sends the keyframe that ends
/// the wait.
///
/// That keyframe is asked for when decryption begins
/// ([LiveKitCubit.renewPicture]). The server sends one as the track is
/// subscribed, which is decoded before decryption begins and so does not
/// count, and a sharer sends no other unasked: the cover waited out its full
/// timeout on almost every stream.
class DecryptedVideo extends StatefulWidget {
  final VideoTrack track;
  final Widget child;

  const DecryptedVideo({super.key, required this.track, required this.child});

  @override
  State<DecryptedVideo> createState() => _DecryptedVideoState();
}

class _DecryptedVideoState extends State<DecryptedVideo> {
  static const _poll = Duration(milliseconds: 100);

  /// A stream is shown after this whatever the counts say.
  static const _giveUpAfter = Duration(seconds: 3);

  /// Tracks whose picture has already come clean. The same track is drawn by
  /// a new widget whenever its tile moves between full size and the stage,
  /// and the SDK reports decryption starting only once per track — so a new
  /// cover waited out its full timeout every time the stream was resized.
  static final Expando<bool> _clean = Expando('clean picture');

  late CleanPictureGate _gate;
  EventsListener<RoomEvent>? _listener;
  Timer? _pollTimer;
  Timer? _giveUpTimer;

  /// Since the cover went up, for the log line saying how it came down.
  final Stopwatch _waited = Stopwatch();

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(DecryptedVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track != widget.track) {
      _stop();
      _start();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _gate = CleanPictureGate();
    _waited
      ..reset()
      ..start();
    if (_clean[widget.track] == true) {
      _gate.giveUp();
      return;
    }
    final room = context.read<LiveKitCubit>().state.room;
    // Nothing to wait for where nothing is encrypted, or on our own track.
    if (widget.track is! RemoteVideoTrack || room?.e2eeManager == null) {
      _gate.giveUp();
      return;
    }
    _listener = room!.createListener()
      ..on<TrackE2EEStateEvent>((e) {
        if (e.publication.track != widget.track) return;
        if (e.state == E2EEState.kOk && !_gate.isDecrypting) _onDecrypting();
      });
    _giveUpTimer = Timer(_giveUpAfter, () => _open(_gate.giveUp, gaveUp: true));
  }

  void _stop() {
    _listener?.dispose();
    _listener = null;
    _pollTimer?.cancel();
    _giveUpTimer?.cancel();
  }

  Future<void> _onDecrypting() async {
    final track = widget.track;
    if (track is RemoteVideoTrack) {
      unawaited(context.read<LiveKitCubit>().renewPicture(track));
    }
    final before = await _keyFrames();
    _gate.onDecrypting(before);
    HelperMethods.printDebug(
      '[Stream] decrypting ${_waited.elapsedMilliseconds} ms after the cover '
      'went up, $before keyframes decoded before; asked for a fresh one',
    );
    _pollTimer = Timer.periodic(_poll, (_) async {
      final count = await _keyFrames();
      _open(() => _gate.onKeyFrames(count));
    });
  }

  Future<int?> _keyFrames() async {
    try {
      final reports = await widget.track.receiver?.getStats();
      return reports == null ? null : keyFramesDecodedIn(reports);
    } catch (_) {
      return null;
    }
  }

  /// Runs [step] and, if it opened the gate, stops waiting and shows the video.
  void _open(VoidCallback step, {bool gaveUp = false}) {
    if (!mounted || _gate.ready) return;
    step();
    if (!_gate.ready) return;
    HelperMethods.printDebug(
      gaveUp
          ? '[Stream] no clean keyframe in ${_waited.elapsedMilliseconds} ms; '
                'shown anyway'
          : '[Stream] clean keyframe ${_waited.elapsedMilliseconds} ms after '
                'the cover went up; shown',
    );
    _clean[widget.track] = true;
    _stop();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_gate.ready)
          ColoredBox(
            color: context.theme.bgSecondary,
            child: Center(
              child: LoadingDots(color: context.theme.textTertiary, dotSize: 4),
            ),
          ),
      ],
    );
  }
}
