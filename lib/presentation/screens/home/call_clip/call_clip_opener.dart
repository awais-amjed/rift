import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/visibility/app_seen_listener.dart';
import '../../../common/server_context_scope.dart';
import '../../../common/show_custom_dialog.dart';
import 'call_clip_dialog.dart';

/// Opens the trim view for each clip the shortcut took
/// ([LiveKitState.pendingClips]), oldest first, one at a time, once anybody
/// can see Rift: a clip taken behind a game waits for the game to go
/// ([AppSeenListener.seenFrom]). In the call's server scope, which is where
/// its soundboard is, whichever server is being read.
class CallClipOpener extends StatefulWidget {
  final Widget child;

  const CallClipOpener({super.key, required this.child});

  @override
  State<CallClipOpener> createState() => _CallClipOpenerState();
}

class _CallClipOpenerState extends State<CallClipOpener> {
  bool _seen = true;
  bool _showing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final seen = AppSeenListener.seenFrom(context);
    if (seen == _seen) return;
    _seen = seen;
    _openNext();
  }

  void _openNext() {
    if (_showing || !_seen || !mounted) return;
    final livekit = context.read<LiveKitCubit>();
    final clip = livekit.state.pendingClips.firstOrNull;
    if (clip == null) return;
    final serverId = livekit.state.callServerId;
    final fromDmCall = livekit.state.dmCall != null;
    livekit.takeClip(clip.id);
    _showing = true;
    unawaited(
      showCustomDialog<void>(
        context: context,
        build: (_) {
          final dialog = CallClipDialog(
            clip: clip,
            fromDmCall: fromDmCall,
            serverId: serverId,
          );
          return serverId == null
              ? dialog
              : ServerContextScope(serverId: serverId, child: dialog);
        },
      ).whenComplete(() {
        _showing = false;
        // The next one, if more were taken meanwhile.
        if (mounted) _openNext();
      }),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<LiveKitCubit, LiveKitState>(
        listenWhen: (before, after) =>
            after.pendingClips.isNotEmpty &&
            before.pendingClips != after.pendingClips,
        listener: (_, _) => _openNext(),
        child: widget.child,
      );
}
