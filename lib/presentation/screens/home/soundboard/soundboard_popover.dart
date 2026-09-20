import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../common/popover_surface.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'widgets/sound_clip_button.dart';
import 'widgets/soundboard_listener_controls.dart';

/// The clips, above the control bar, while in a call.
///
/// A list rather than a grid of glyphs: what a person is looking for here is
/// a name, under time pressure, and a wall of emoji is a puzzle. It stays
/// open after a press — pressing two in a row is the normal case, and a
/// popover that closed each time would make that four clicks.
class SoundboardPopover extends StatelessWidget {
  /// Whether this member may fire one. False leaves the clips on screen and
  /// unpressable, rather than hiding a library that is plainly there: the
  /// absence of a button with no explanation reads as a bug.
  final bool canPlay;

  const SoundboardPopover({super.key, required this.canPlay});

  static const double width = 260;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return SizedBox(
      width: width,
      child: PopoverSurface(
        padding: const EdgeInsets.all(12),
        child: BlocBuilder<SoundboardCubit, SoundboardState>(
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SOUNDBOARD',
                  style: AppText.sectionLabel.copyWith(
                    color: theme.textTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                if (state.status == SoundboardStatus.loading)
                  _note(context, 'Loading…')
                else if (state.status == SoundboardStatus.error)
                  _note(context, state.error ?? 'Could not load the clips.')
                else if (state.isEmpty)
                  _note(
                    context,
                    'No clips yet. Somebody who can manage the server adds '
                    'them under Manage server → Soundboard.',
                  )
                else ...[
                  if (!canPlay)
                    _note(
                      context,
                      'You cannot play clips on this server — everything '
                      'below is somebody else\'s to press.',
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 264),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final sound in state.sounds) ...[
                            SoundClipButton(
                              sound: sound,
                              justPressed: state.pressed.contains(sound.id),
                              onTap: canPlay
                                  ? () => context.read<SoundboardCubit>().press(
                                      sound,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 4),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Divider(color: theme.borderPrimary, height: 13),
                const SoundboardListenerControls(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _note(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: AppText.rowQuiet.copyWith(color: context.theme.textTertiary),
    ),
  );
}
