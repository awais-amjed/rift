import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/soundboard_sound.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../../../../logic/services/byte_format.dart';
import '../../../../../../../logic/services/soundboard_staging.dart';
import '../../../../../../common/app_button.dart';
import '../../../../../../common/app_text_field.dart';
import '../../../../../../common/loading_dots.dart';
import '../../../../../../theme/app_text.dart';
import '../../../../../../theme/custom_colors.dart';
import '../../../../../../theme/theme_context.dart';

/// Over the widget budget and one job: one clip and its three actions, one of
/// which is an inline edit.
///
/// One clip in the manage list: what it is, and the three things that can be
/// done to it.
///
/// Preview plays it **here only**, through the same path a listener takes —
/// nothing is sent to the room. Adding a clip without being able to hear it
/// first is how a server ends up with three airhorns and no idea which is
/// which.
///
/// Rename edits in place rather than opening a dialog. Changing one word is
/// not a trip, and making it one is what leaves the typo there — which used
/// to cost a delete and a re-upload, since `rename` existed in the cubit
/// with nothing calling it.
///
/// Only the name and the glyph. The file behind a clip is not editable and
/// must not look it: `object_path` is minted once and the schema has no
/// UPDATE grant on it, so "replace the sound" is a thing the server refuses
/// by design.
class SoundboardClipRow extends StatefulWidget {
  final SoundboardSound sound;
  final bool busy;
  final VoidCallback onRemove;

  const SoundboardClipRow({
    super.key,
    required this.sound,
    required this.busy,
    required this.onRemove,
  });

  @override
  State<SoundboardClipRow> createState() => _SoundboardClipRowState();
}

class _SoundboardClipRowState extends State<SoundboardClipRow> {
  final _nameCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();

  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  void _startEditing() {
    _nameCtrl.text = widget.sound.name;
    _emojiCtrl.text = widget.sound.emoji ?? '';
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    final rejection = SoundboardStaging.rejectionForName(name);
    if (rejection != null) {
      setState(() => _error = rejection);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final emoji = _emojiCtrl.text.trim();
    // An empty field clears it: `rename` passes clearEmoji when the emoji
    // is null, so there is a way back from a glyph somebody regrets.
    final error = await context.read<SoundboardCubit>().rename(
      sound: widget.sound,
      name: name,
      emoji: emoji.isEmpty ? null : emoji,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      if (error == null) _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(
          color: _editing ? theme.channelActiveBorder : theme.borderPrimary,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dimmed as a whole while something is happening to it, rather
          // than only greying the one button: a slow removal that leaves the
          // row looking untouched reads as a press that was ignored.
          Opacity(
            opacity: widget.busy ? 0.5 : 1,
            child: _editing ? _editor(context) : _summary(context),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(
              error,
              style: AppText.rowQuiet.copyWith(color: CustomColors.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final theme = context.theme;
    final sound = widget.sound;
    final author = sound.createdBy == null
        ? null
        : context
              .watch<ServerMembersCubit>()
              .state
              .byId[sound.createdBy]
              ?.displayName;

    return Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            sound.emoji ?? '♪',
            style: AppText.row.copyWith(
              color: sound.emoji == null
                  ? theme.textQuaternary
                  : theme.textPrimary,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sound.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.row.copyWith(color: theme.textPrimary),
              ),
              Text(
                [
                  SoundboardStaging.durationLabel(sound.duration),
                  humanSize(sound.bytes),
                  if (author != null) 'added by $author',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowQuiet.copyWith(color: theme.textQuaternary),
              ),
            ],
          ),
        ),
        if (widget.busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LoadingDots(color: context.theme.accentBright, dotSize: 4),
          )
        else ...[
          IconButton(
            tooltip: 'Play it here',
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            color: theme.textSecondary,
            onPressed: () => context.read<SoundboardCubit>().preview(sound),
          ),
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: theme.textTertiary,
            onPressed: _startEditing,
          ),
          // An icon, not a button with a word on it. `QuietDangerButton` is
          // sized to be one option among several in a stacked list; in a
          // dense row it is a slab of red beside two bare glyphs, and it
          // reads as the point of the row rather than as the thing you
          // reach for once. The weight this action needs is carried by the
          // confirmation it opens, not by the control that opens it.
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            color: theme.textTertiary,
            hoverColor: CustomColors.error.withValues(alpha: 0.10),
            // Red on approach rather than at rest: enough to say what it
            // does before it is pressed, quiet enough to stay in a list.
            style: ButtonStyle(
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered)
                    ? CustomColors.error
                    : theme.textTertiary,
              ),
            ),
            onPressed: widget.onRemove,
          ),
        ],
      ],
    );
  }

  Widget _editor(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          child: AppTextField(
            controller: _emojiCtrl,
            hint: '📯',
            maxLength: 8,
            enabled: !_saving,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppTextField(
            controller: _nameCtrl,
            hint: 'airhorn',
            maxLength: SoundboardStaging.maxNameLength,
            autofocus: true,
            enabled: !_saving,
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(width: 10),
        AppButton(label: 'Save', isLoading: _saving, onPressed: _save),
        const SizedBox(width: 6),
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _saving ? null : () => setState(() => _editing = false),
        ),
      ],
    );
  }
}
