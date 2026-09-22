import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../../../../../data/repositories/soundboard_repository.dart';
import '../../../../../../../logic/services/byte_format.dart';
import '../../../../../../../logic/services/mime_util.dart';
import '../../../../../../../logic/services/soundboard_play.dart';
import '../../../../../../../logic/services/soundboard_staging.dart';
import '../../../../../../common/app_button.dart';
import '../../../../../../common/app_text_field.dart';
import '../../../../../../theme/app_text.dart';
import '../../../../../../theme/custom_colors.dart';
import '../../../../../../theme/theme_context.dart';

/// Over the widget budget and one job: a form: pick a file, name it, add it.
///
/// Picking a file, naming it, and adding it.
///
/// The file comes first and the name is prefilled from it, because that is
/// the order the decision is actually made in: somebody has a clip and wants
/// it here, not a name looking for a sound.
class AddClipForm extends StatefulWidget {
  /// Whether the board is already full. The form stays, with the button
  /// disabled and the reason printed, rather than disappearing — an absent
  /// control explains nothing.
  final bool full;

  final Future<String?> Function({
    required String name,
    String? emoji,
    required Uint8List bytes,
    required String contentType,
    required Duration duration,
  })
  onAdd;

  const AddClipForm({super.key, required this.full, required this.onAdd});

  @override
  State<AddClipForm> createState() => _AddClipFormState();
}

class _AddClipFormState extends State<AddClipForm> {
  final _nameCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();

  Uint8List? _bytes;
  String? _fileName;
  String? _mime;
  Duration _duration = Duration.zero;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _error = null);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Audio', extensions: SoundboardStaging.extensions),
      ],
    );
    if (file == null) return;

    final mime = (file.mimeType?.isNotEmpty ?? false)
        ? file.mimeType!
        : mimeFromName(file.name);
    final bytes = await file.readAsBytes();
    final rejection = SoundboardStaging.rejectionFor(
      fileName: file.name,
      mime: mime,
      bytes: bytes.length,
    );
    if (!mounted) return;
    if (rejection != null) {
      setState(() => _error = rejection);
      return;
    }

    // Measured by the stack that will play it, before anything is uploaded.
    final duration = await SoundboardStaging.measure(bytes, path: file.path);
    if (!mounted) return;
    // The length is the one rule that cannot be checked from the file's name
    // or its size, so it is asked here rather than in `rejectionFor` — and
    // it is asked at the moment of picking, which is the last point where
    // trimming the file is still an option the uploader has.
    final tooLong = SoundboardStaging.rejectionForDuration(
      fileName: file.name,
      duration: duration,
    );
    if (tooLong != null) {
      setState(() => _error = tooLong);
      return;
    }
    setState(() {
      _bytes = bytes;
      _fileName = file.name;
      _mime = mime;
      _duration = duration;
      if (_nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = _defaultName(file.name);
      }
    });
  }

  /// The file's name without its extension, cut to what the column takes.
  static String _defaultName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot <= 0 ? fileName : fileName.substring(0, dot);
    return stem.length <= SoundboardStaging.maxNameLength
        ? stem
        : stem.substring(0, SoundboardStaging.maxNameLength);
  }

  Future<void> _add() async {
    final bytes = _bytes;
    if (bytes == null || _busy) return;

    final rejection = SoundboardStaging.rejectionForName(_nameCtrl.text);
    if (rejection != null) {
      setState(() => _error = rejection);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final emoji = _emojiCtrl.text.trim();
    final error = await widget.onAdd(
      name: _nameCtrl.text.trim(),
      emoji: emoji.isEmpty ? null : emoji,
      bytes: bytes,
      contentType: _mime ?? 'application/octet-stream',
      duration: _duration,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) {
        _bytes = null;
        _fileName = null;
        _mime = null;
        _duration = Duration.zero;
        _nameCtrl.clear();
        _emojiCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final picked = _bytes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppButton(
              label: picked == null ? 'Choose a file' : 'Choose another',
              variant: AppButtonVariant.secondary,
              icon: const Icon(Icons.audiotrack_rounded, size: 17),
              onPressed: _busy ? null : _pick,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                picked == null
                    ? 'Up to ${humanSize(SoundboardRepository.maxBytes)} and '
                          '${SoundboardStaging.durationLabel(SoundboardPlay.maxPlayback)}, '
                          '${SoundboardStaging.extensions.join(', ')}.'
                    : '$_fileName · ${humanSize(picked.length)} · '
                          '${SoundboardStaging.durationLabel(_duration)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.rowQuiet.copyWith(color: theme.textTertiary),
              ),
            ),
          ],
        ),
        if (picked != null) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Name',
                  controller: _nameCtrl,
                  hint: 'airhorn',
                  maxLength: SoundboardStaging.maxNameLength,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 92,
                child: AppTextField(
                  label: 'Emoji',
                  controller: _emojiCtrl,
                  hint: '📯',
                  maxLength: 8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppButton(
            label: widget.full ? 'Soundboard full' : 'Add clip',
            isLoading: _busy,
            onPressed: widget.full ? null : _add,
          ),
        ],
        if (_error case final error?) ...[
          const SizedBox(height: 10),
          Text(
            error,
            style: AppText.rowQuiet.copyWith(color: CustomColors.error),
          ),
        ],
      ],
    );
  }
}
