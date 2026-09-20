import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../theme/app_motion.dart';
import 'widgets/soundboard_activity_chip.dart';

/// The stack of "who played what" chips, just above the control bar.
///
/// Anchored to the bar rather than to the window, so it clears the bar on
/// every platform and does not end up behind a sheet on a phone.
///
/// It rides focus mode with the bar, with one exception: while a chip is
/// live it stays *pressable*. If the chrome has faded because nobody has
/// moved the mouse, a clip arriving over bare video is precisely the thing
/// that should still be reachable — that is the moment the button exists
/// for.
class SoundboardActivity extends StatelessWidget {
  /// Whether the chrome is showing. Only fades the chips; it does not take
  /// their taps away.
  final bool visible;

  /// How far above the bottom of the stage the newest chip sits — clear of
  /// the control bar, which is what it is answering for.
  static const double bottomInset = 90;

  const SoundboardActivity({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SoundboardCubit, SoundboardState>(
      buildWhen: (before, after) => before.recent != after.recent,
      builder: (context, state) {
        if (state.recent.isEmpty) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset,
          child: Center(
            child: AnimatedOpacity(
              // Faded with the chrome, never hidden: a chip is the answer to
              // a noise the room just heard, and the answer arriving
              // invisibly is no answer.
              opacity: visible ? 1 : 0.85,
              duration: AppMotion.enter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Newest last, so it sits nearest the bar and the older
                  // ones rise away from the hand.
                  for (final heard in state.recent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SoundboardActivityChip(
                        key: ValueKey(heard.id),
                        heard: heard,
                        newest: heard.id == state.recent.last.id,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
