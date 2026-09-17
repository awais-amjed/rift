import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../../data/constants.dart';
import '../../../../logic/services/screen_share_sources.dart';
import '../../../../src/rust/api/screenshare/types.dart';
import '../../../common/app_button.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'widgets/audio_source_row.dart';

/// Picks the application whose sound to share.
///
/// Everything currently playing, and nothing else: the list is what the
/// platform reports as live playback streams, so an application that is open
/// but silent is not here to be chosen. That is the one thing people trip over,
/// so the empty state says it outright instead of just being empty.
///
/// Returns the chosen source, or null if the dialog was dismissed.
class SoundSharePickerDialog extends StatefulWidget {
  const SoundSharePickerDialog({super.key});

  @override
  State<SoundSharePickerDialog> createState() => _SoundSharePickerDialogState();
}

class _SoundSharePickerDialogState extends State<SoundSharePickerDialog> {
  List<AudioSource>? _sources;
  AudioSource? _selected;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sources = await ScreenShareSources.listAudio();
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _loading = false;
      // Re-resolved rather than kept: a source compares on every field, and
      // the one you had in hand is stale the moment the track changes.
      _selected = ScreenShareSources.pickAudioSource(sources, _selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Dialog(
      backgroundColor: theme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(K.radiusCard),
        side: BorderSide(color: theme.borderPrimary),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: max(440, 40.w),
          maxHeight: max(520, 70.h),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              Divider(height: 24, color: theme.borderPrimary),
              Flexible(child: _body()),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 10,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  AppButton(
                    label: 'Share sound',
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.of(context).pop(_selected),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final theme = context.theme;
    return Row(
      spacing: 10,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(K.radiusRow),
          ),
          child: Icon(Icons.music_note_rounded, size: 18, color: theme.primary),
        ),
        Expanded(
          child: Text(
            'Share sound',
            style: AppText.dialogTitle.copyWith(color: theme.textPrimary),
          ),
        ),
        IconButton(
          onPressed: _loading ? null : _load,
          tooltip: 'Refresh',
          icon: Icon(Icons.refresh, size: 18, color: theme.textQuaternary),
        ),
      ],
    );
  }

  Widget _body() {
    final theme = context.theme;
    if (_loading && _sources == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final sources = _sources ?? const <AudioSource>[];
    if (sources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          spacing: 8,
          children: [
            Icon(Icons.volume_off_rounded, color: theme.textTertiary),
            Text(
              'Nothing is playing',
              style: AppText.row.copyWith(color: theme.textSecondary),
            ),
            Text(
              'Start playing something in an app, then refresh.',
              textAlign: TextAlign.center,
              style: AppText.secondary.copyWith(color: theme.textTertiary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final source = sources[index];
        return AudioSourceRow(
          source: source,
          selected: source == _selected,
          onTap: () => setState(() => _selected = source),
        );
      },
    );
  }
}
