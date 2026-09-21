import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../common/user_avatar.dart';
import '../../../../responsive/shell_scope.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// One line saying **who** played **what**, and offering the one thing
/// somebody wants at that second.
///
/// This is the only moment anybody knows they want it. A per-person
/// soundboard mute reached from a settings page is a control you go looking
/// for having already forgotten whose airhorn it was; reached from here it
/// is one tap on the person, while the sound is still in the air.
///
/// It writes the soundboard key and not the voice one — muting somebody's
/// clips is not an accusation, and taking their voice for it would be the
/// wrong answer to the only complaint anybody has.
class SoundboardActivityChip extends StatefulWidget {
  final SoundboardHeard heard;

  /// Whether this is the newest chip. The ones above it have begun to go and
  /// say so by dimming — they do not reflow when one expires, because a
  /// stack that shuffles while you are reaching for it is a stack you cannot
  /// press.
  final bool newest;

  const SoundboardActivityChip({
    super.key,
    required this.heard,
    required this.newest,
  });

  @override
  State<SoundboardActivityChip> createState() => _SoundboardActivityChipState();
}

class _SoundboardActivityChipState extends State<SoundboardActivityChip> {
  bool _hovered = false;

  /// Set the moment the mute is applied. The chip becomes its own receipt
  /// rather than raising a toast: an undo has to be where the thing you just
  /// did was, and somebody who mis-tapped mid-call will not go hunting for
  /// it somewhere else.
  bool _muted = false;

  /// How long the receipt stays. Longer than the chip's own life, because
  /// reading what happened and deciding to take it back is two thoughts.
  static const Duration _receipt = Duration(seconds: 4);

  void _hover(bool on) {
    setState(() => _hovered = on);
    final cubit = context.read<SoundboardCubit>();
    // A 2.4s window you cannot hit is not an affordance, and the button
    // lives inside it.
    if (on) {
      cubit.holdHeard(widget.heard.id);
    } else {
      cubit.releaseHeard(widget.heard.id);
    }
  }

  void _mute() {
    context.read<AppCubit>().setSoundboardMutedFor(widget.heard.userId, true);
    setState(() => _muted = true);
    context.read<SoundboardCubit>().releaseHeard(
      widget.heard.id,
      after: _receipt,
    );
  }

  void _undo() {
    context.read<AppCubit>().setSoundboardMutedFor(widget.heard.userId, false);
    context.read<SoundboardCubit>().dismissHeard(widget.heard.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final member = context
        .watch<ServerMembersCubit>()
        .state
        .byId[widget.heard.userId];
    // Drawn with the id's own gradient and initial if the roster has never
    // heard of them: waiting for a name would mean the chip arrives after
    // the sound it is explaining.
    final name = member?.displayName ?? 'Someone';
    final avatarPath = member?.avatarPath;
    final sound = context
        .watch<SoundboardCubit>()
        .state
        .sounds
        .where((s) => s.id == widget.heard.soundId)
        .firstOrNull;

    return MouseRegion(
      onEnter: (_) => _hover(true),
      onExit: (_) => _hover(false),
      child: AnimatedOpacity(
        opacity: widget.newest || _hovered ? 1 : 0.55,
        duration: AppMotion.state,
        child: Container(
          decoration: BoxDecoration(
            color: theme.bgElevated,
            borderRadius: BorderRadius.circular(K.radiusPill),
            border: Border.all(color: theme.borderElevated),
            boxShadow: AppShadows.popover,
          ),
          padding: const EdgeInsets.fromLTRB(10, 5, 5, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _muted
                ? _receiptRow(context, name)
                : _playedRow(
                    context,
                    name,
                    avatarPath,
                    sound?.emoji,
                    sound?.name,
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _playedRow(
    BuildContext context,
    String name,
    String? avatarPath,
    String? emoji,
    String? clip,
  ) {
    final theme = context.theme;
    return [
      Text(emoji ?? '♪', style: AppText.row.copyWith(color: theme.textPrimary)),
      const SizedBox(width: 9),
      UserAvatar(
        avatarPath: avatarPath,
        name: name,
        size: 22,
        seed: widget.heard.userId,
      ),
      const SizedBox(width: 8),
      Text(name, style: AppText.strong.copyWith(color: theme.textPrimary)),
      const SizedBox(width: 6),
      Text(
        'played',
        style: AppText.secondary.copyWith(color: theme.textTertiary),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          clip ?? 'a clip',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.row.copyWith(color: theme.textSecondary),
        ),
      ),
      const SizedBox(width: 8),
      _MuteButton(
        // No hover on a touchscreen, so the word is simply always there and
        // the target is the whole right end.
        label: context.layoutMode.isCompact
            ? 'Mute'
            : (_hovered ? 'Mute $name' : null),
        onTap: _mute,
      ),
    ];
  }

  List<Widget> _receiptRow(BuildContext context, String name) {
    final theme = context.theme;
    return [
      Icon(Icons.volume_off_rounded, size: 16, color: theme.textTertiary),
      const SizedBox(width: 9),
      Flexible(
        child: Text(
          "$name's clips are muted here",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.row.copyWith(color: theme.textSecondary),
        ),
      ),
      const SizedBox(width: 8),
      _MuteButton(label: 'Undo', quiet: true, onTap: _undo),
    ];
  }
}

/// The chip's one control: a glyph until the pointer is on it, then a word.
class _MuteButton extends StatelessWidget {
  /// Null draws the glyph alone — the resting desktop state.
  final String? label;
  final bool quiet;
  final VoidCallback onTap;

  const _MuteButton({this.label, this.quiet = false, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final color = quiet ? theme.textSecondary : CustomColors.error;
    final radius = BorderRadius.circular(K.radiusPill);

    return Material(
      color: label == null
          ? Colors.transparent
          : (quiet
                ? theme.bgHover
                : CustomColors.error.withValues(alpha: 0.10)),
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          height: 30,
          constraints: const BoxConstraints(minWidth: 30),
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 11),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: label == null
                ? null
                : Border.all(
                    color: quiet
                        ? theme.borderElevated
                        : CustomColors.error.withValues(alpha: 0.25),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!quiet) ...[
                Icon(
                  Icons.volume_off_rounded,
                  size: label == null ? 17 : 15,
                  color: label == null ? theme.textTertiary : color,
                ),
                if (label != null) const SizedBox(width: 6),
              ],
              if (label != null)
                Text(
                  label!,
                  style: AppText.secondaryStrong.copyWith(color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
