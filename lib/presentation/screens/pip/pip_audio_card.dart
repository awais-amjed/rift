import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../theme/app_text.dart';
import '../../theme/media_colors.dart';

/// What the floating window shows when the call has nothing to look at.
///
/// The window is only armed while someone's camera or screen is live, so this
/// is the case where that ended after the app was already floating — an empty
/// black rectangle would read as the app having crashed. It says the call is
/// still up, and whether the mic is.
class PipAudioCard extends StatelessWidget {
  const PipAudioCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BlocBuilder<LiveKitCubit, LiveKitState>(
        buildWhen: (a, b) => a.isMicOn != b.isMicOn,
        builder: (context, state) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                state.isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                size: 28,
                color: MediaColors.onMediaSecondary,
              ),
              const SizedBox(height: 6),
              Text(
                'In a call',
                style: AppText.body.copyWith(
                  color: MediaColors.onMediaSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
