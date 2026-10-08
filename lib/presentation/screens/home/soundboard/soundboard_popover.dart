import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../common/popover_surface.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'widgets/sound_clip_button.dart';
import 'widgets/soundboard_listener_controls.dart';

/// The clips, while in a call.
///
/// A list rather than a grid of glyphs: what a person is looking for here is
/// a name, under time pressure, and a wall of emoji is a puzzle. It stays
/// open after a press — pressing two in a row is the normal case, and a
/// picker that closed each time would make that four taps.
///
/// Two shells, one list. On a pointer platform it is a card anchored to the
/// button, which is the right object there. On a phone it is the body of a
/// bottom sheet: a hand-rolled overlay pinned to a control at the bottom of
/// the screen is a card under the thumb that opened it.
class SoundboardPopover extends StatelessWidget {
  /// The most the whole card may take — on a short window, what there is
  /// between the button and the top of the screen. The clip list gives up
  /// the space, so a cramped window shortens the list instead of pushing
  /// the header off the top, which is what an unclamped `bottom:` did.
  final double? maxHeight;

  /// A sheet rather than a card: bigger rows, no surface of its own.
  final bool compact;

  const SoundboardPopover({super.key, this.maxHeight, this.compact = false});

  static const double width = 260;

  /// What the clip list takes when there is no ceiling to divide up.
  static const double _listHeight = 264;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 9),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: context.theme.textPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(K.radiusPill),
                ),
              ),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: _body(context),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
        child: PopoverSurface(
          padding: const EdgeInsets.all(12),
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = context.theme;

    // Rebuilt when the viewer's own permissions move, not only when the
    // library does: both of these were read once as the picker opened and
    // passed in, so a role granted or revoked mid-call left it wrong in
    // whichever direction it was wrong.
    return BlocBuilder<ServerCubit, ServerState>(
      buildWhen: (before, after) =>
          before.selectedServer?.user?.permissions !=
          after.selectedServer?.user?.permissions,
      builder: (context, server) {
        final permissions = server.myPermissions;
        final canPlay =
            permissions?.can(ServerPermission.useSoundboard) ?? false;
        final canManage =
            permissions?.can(ServerPermission.manageSoundboard) ?? false;

        return BlocBuilder<SoundboardCubit, SoundboardState>(
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
                SizedBox(height: compact ? 10 : 8),
                if (state.status == SoundboardStatus.loading)
                  _note(context, 'Loading…')
                else if (state.status == SoundboardStatus.error)
                  _note(context, state.error ?? 'Could not load the clips.')
                else if (state.isEmpty)
                  // The button is only shown on an empty board to somebody
                  // who can fill it, so telling *them* that somebody who can
                  // manage the server does it is the app talking about the
                  // reader in the third person.
                  _note(
                    context,
                    canManage
                        ? 'No clips yet. Add one under Manage server → '
                              'Soundboard.'
                        : 'No clips yet. Somebody who can manage the server '
                              'adds them under Manage server → Soundboard.',
                  )
                else ...[
                  if (!canPlay)
                    _note(
                      context,
                      'You cannot play clips on this server — everything '
                      'below is somebody else\'s to press.',
                    ),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: maxHeight == null && !compact
                            ? _listHeight
                            : double.infinity,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final sound in state.sounds) ...[
                              SoundClipButton(
                                sound: sound,
                                compact: compact,
                                justPressed: state.pressed.contains(sound.id),
                                onTap: canPlay
                                    ? () => context
                                          .read<SoundboardCubit>()
                                          .press(sound)
                                    : null,
                              ),
                              SizedBox(height: compact ? 6 : 4),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 8 : 6),
                Divider(color: theme.borderPrimary, height: compact ? 15 : 13),
                SoundboardListenerControls(compact: compact),
              ],
            );
          },
        );
      },
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
