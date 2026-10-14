import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';

import '../../../../../data/classes/shared_window.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/services/process_tree.dart';
import '../../../../../logic/services/screen_share_sources.dart';
import '../../../../../logic/services/share_sound_match.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/app_button.dart';
import '../../../../common/checkbox_row.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../sections/audio_source_section.dart';

/// What the sound popup was answered with: the app whose sound goes with the
/// window (null for every app but Rift), and whether to keep it for the
/// window's app.
typedef ShareSoundAnswer = ({AudioSource? source, bool remember});

/// Linux: which sound goes out with the window just picked, asked after the
/// pick, with the app [ShareSoundMatch] thinks is the window's already
/// chosen. Returns null when dismissed, which cancels the share.
class ShareSoundDialog extends StatefulWidget {
  /// The window being shared, or null when the desktop did not say: then
  /// there is no guess and nothing to remember the answer by.
  final SharedWindow? window;

  const ShareSoundDialog({super.key, required this.window});

  @override
  State<ShareSoundDialog> createState() => _ShareSoundDialogState();
}

class _ShareSoundDialogState extends State<ShareSoundDialog> {
  List<AudioSource>? _sources;
  AudioSource? _selected;
  bool _loading = false;
  bool _remember = false;

  /// Whether the user picked by hand. Until then a reload guesses again, so
  /// an app that starts playing after the popup opened is still found.
  bool _picked = false;

  /// What a ticked Remember keeps the answer under ([ShareSoundMatch.appKey]),
  /// or null when there is nothing to keep it by and no box is shown.
  String? _key;

  @override
  void initState() {
    super.initState();
    final window = widget.window;
    _key = window == null ? null : ShareSoundMatch.appKey(window);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sources = await ScreenShareSources.listAudio();
    if (!mounted) return;
    final window = widget.window;
    setState(() {
      _sources = sources;
      _loading = false;
      _selected = _picked
          ? ScreenShareSources.keepAudioSource(sources, _selected)
          : window == null
          ? null
          : ShareSoundMatch.guess(
              window,
              sources,
              parentOf: ProcessTree.parentOf,
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final window = widget.window;
    final title = window?.title ?? '';
    return Dialog(
      backgroundColor: theme.bgElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(K.radiusCard),
        side: BorderSide(color: theme.borderPrimary),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max(440, 40.w)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sound for this window',
                style: AppText.dialogTitle.copyWith(color: theme.textPrimary),
              ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.secondary.copyWith(color: theme.textTertiary),
                ),
              ],
              Divider(height: 24, color: theme.borderPrimary),
              AudioSourceSection(
                audioSources: _sources,
                selectedAudioSource: _selected,
                isLoading: _loading && _sources == null,
                onChanged: (source) => setState(() {
                  _selected = source;
                  _picked = true;
                }),
                onRefresh: _load,
              ),
              if (_key != null) ...[
                const SizedBox(height: 8),
                CheckboxRow(
                  label: ShareSoundMatch.byTitle(_key!)
                      ? 'Remember for this window'
                      : 'Remember for this app',
                  value: _remember,
                  onChanged: (value) => setState(() => _remember = value),
                ),
              ],
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
                    label: 'Start sharing',
                    onPressed: _sources == null
                        ? null
                        : () => Navigator.of(context).pop<ShareSoundAnswer>((
                            source: _selected,
                            remember: _remember,
                          )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
