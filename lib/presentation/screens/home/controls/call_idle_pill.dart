import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/services/call_duration.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';

/// What stays on screen when a phone's call controls fade: the call's length
/// and your mic, and a word saying a tap brings the rest back.
///
/// Hiding the bar must never hide whether you can be heard. On a desktop the
/// pointer brings the bar back just by moving; a finger has to know to tap.
class CallIdlePill extends StatefulWidget {
  final bool visible;

  const CallIdlePill({super.key, required this.visible});

  @override
  State<CallIdlePill> createState() => _CallIdlePillState();
}

class _CallIdlePillState extends State<CallIdlePill> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.visible) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final call = context.watch<LiveKitCubit>().state;
    final at = call.connectedAt;
    final micOn = call.isMicOn;

    return Positioned(
      bottom: K.callBarOffset,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          child: AnimatedOpacity(
            opacity: widget.visible ? 1 : 0,
            duration: AppMotion.enter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: theme.bgElevated.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(K.radiusPill),
                border: Border.all(color: theme.borderElevated),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  const Icon(
                    Icons.graphic_eq_rounded,
                    size: 15,
                    color: CustomColors.success,
                  ),
                  Text(
                    at == null
                        ? '--:--'
                        : formatCallDuration(DateTime.now().difference(at)),
                    style: AppText.figure.copyWith(color: theme.textPrimary),
                  ),
                  Container(width: 1, height: 14, color: theme.borderElevated),
                  Icon(
                    micOn ? Icons.mic_none_rounded : Icons.mic_off_rounded,
                    size: 15,
                    color: micOn ? theme.textTertiary : CustomColors.error,
                  ),
                  Text(
                    'Tap for controls',
                    style: AppText.meta.copyWith(color: theme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
