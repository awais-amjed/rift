import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/classes/call_clip_audio.dart';
import '../../../../data/constants.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/call_clip/clip_trim.dart';
import '../../../../logic/services/clock_time.dart';
import '../../../../src/rust/api/call_clip.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/chat/attachments/attachment_download.dart';
import '../../../common/server_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../servers/manage/panels/soundboard/add_clip_form.dart';
import 'widgets/clip_actions.dart';
import 'widgets/clip_play_line.dart';
import 'widgets/clip_preview_button.dart';
import 'widgets/clip_trim_handles.dart';
import 'widgets/clip_waveform.dart';

/// A clip of the call, to trim and then save as a WAV or put on the call's
/// soundboard as an MP3 (CALLS.md, "Clipping a call"). Opened by
/// [CallClipOpener] in the call's server scope, with its own copy of the
/// audio: the ring keeps running, and the call can end under it.
class CallClipDialog extends StatefulWidget {
  final CallClipAudio clip;

  /// Whether it came from a DM call, as it was when clipped: a DM has no
  /// soundboard, whatever server it is on.
  final bool fromDmCall;

  const CallClipDialog({
    super.key,
    required this.clip,
    required this.fromDmCall,
  });

  /// The soundboard's bitrate: a clip up to its 30 s fits well inside 5 MB.
  static const int kbps = 192;

  @override
  State<CallClipDialog> createState() => _CallClipDialogState();
}

class _CallClipDialogState extends State<CallClipDialog> {
  static const int _bars = 240;

  /// The shortest selection, so a handle cannot be dragged onto the other.
  static const Duration _shortest = Duration(milliseconds: 500);

  late final List<double> _peaks;

  /// How far the preview has played, for the line over the waveform.
  final ValueNotifier<Duration?> _played = ValueNotifier(null);
  double _start = 0;
  double _end = 1;
  bool _saving = false;
  bool _encoding = false;

  /// The selection as an MP3, once Add to soundboard has encoded it: the
  /// soundboard's own form is shown for it.
  ({Uint8List bytes, Duration length})? _forBoard;

  CallClipAudio get _clip => widget.clip;
  Duration _at(double fraction) => _clip.duration * fraction;
  Duration get _length => _at(_end) - _at(_start);

  Int16List _selection() => ClipTrim.cut(
    _clip.pcm,
    _clip.channels,
    _at(_start),
    _at(_end),
    rate: _clip.rate,
  );

  @override
  void initState() {
    super.initState();
    _peaks = ClipTrim.peaks(_clip.pcm, _clip.channels, _bars);
  }

  @override
  void dispose() {
    _played.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final wav = await callClipWav(
        pcm: _selection(),
        rate: _clip.rate,
        channels: _clip.channels,
      );
      if (!mounted) return;
      await saveToDisk(context, ClipTrim.fileName(_clip.at, 'wav'), wav);
    } catch (e) {
      HelperMethods.printDebug('[Clips] save failed: $e');
      HelperMethods.showError(error: "Couldn't save the clip.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _encodeForBoard() async {
    setState(() => _encoding = true);
    final length = _length;
    try {
      final mp3 = await callClipMp3(
        pcm: _selection(),
        rate: _clip.rate,
        channels: _clip.channels,
        kbps: CallClipDialog.kbps,
      );
      if (!mounted) return;
      setState(() => _forBoard = (bytes: mp3, length: length));
    } catch (e) {
      HelperMethods.printDebug('[Clips] MP3 failed: $e');
      HelperMethods.showError(error: "Couldn't make the clip an MP3.");
    } finally {
      if (mounted) setState(() => _encoding = false);
    }
  }

  Future<String?> _addToBoard({
    required String name,
    String? emoji,
    required Uint8List bytes,
    required String contentType,
    required Duration duration,
  }) async {
    final error = await context.read<SoundboardCubit>().add(
      name: name,
      emoji: emoji,
      bytes: bytes,
      contentType: contentType,
      duration: duration,
    );
    if (error == null && mounted) {
      Navigator.of(context).pop();
      HelperMethods.showToast(
        title: 'Added to the soundboard',
        description: name,
      );
    }
    return error;
  }

  @override
  Widget build(BuildContext context) {
    final serverId = ServerScope.of(context).serverId;
    final canManage = context.select<ServerCubit, bool>(
      (cubit) =>
          cubit.state
              .permissionsOn(serverId)
              ?.can(ServerPermission.manageSoundboard) ??
          false,
    );
    final outputId = context.select<AppCubit, String?>(
      (cubit) => cubit.state.callOutputId,
    );
    final full = context.select<SoundboardCubit, bool>(
      (cubit) => cubit.state.sounds.length >= SoundboardCubit.maxSounds,
    );
    final forBoard = _forBoard;
    if (forBoard != null) return _boardForm(forBoard, full: full);

    final theme = context.theme;
    final meta = AppText.meta.copyWith(color: theme.textTertiary);
    final total = _clip.duration;
    return AppModal(
      title: 'Clip',
      subtitle:
          'Clipped at ${formatClock(_clip.at)} · '
          '${ClipTrim.timeLabel(_length)} selected',
      titleIcon: const Icon(Icons.content_cut_rounded, size: K.iconButton),
      maxWidth: 600,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 96,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: theme.bgTertiary,
              borderRadius: BorderRadius.circular(K.radiusRow),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipWaveform(peaks: _peaks, start: _start, end: _end),
                ClipPlayLine(
                  played: _played,
                  start: _start,
                  end: _end,
                  length: _length,
                ),
                ClipTrimHandles(
                  start: _start,
                  end: _end,
                  minGap: total > _shortest
                      ? _shortest.inMicroseconds / total.inMicroseconds
                      : 1,
                  onChanged: (start, end) => setState(() {
                    _start = start;
                    _end = end;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(ClipTrim.timeLabel(_at(_start)), style: meta),
              const Spacer(),
              Text(ClipTrim.timeLabel(_at(_end)), style: meta),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipPreviewButton(
                // A new selection is a new preview, and stops the old one.
                key: ValueKey((_start, _end)),
                selection: _selection,
                rate: _clip.rate,
                channels: _clip.channels,
                outputId: outputId,
                played: _played,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipActions(
                  wavBytes: ClipTrim.wavBytes(_length),
                  mp3Bytes: ClipTrim.mp3Bytes(_length, CallClipDialog.kbps),
                  saving: _saving,
                  adding: _encoding,
                  onSave: _save,
                  onAdd: canManage && !widget.fromDmCall
                      ? _encodeForBoard
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The soundboard's add form, handed the MP3: its name, emoji and refusals.
  Widget _boardForm(
    ({Uint8List bytes, Duration length}) forBoard, {
    required bool full,
  }) {
    return AppModal(
      title: 'Add to soundboard',
      maxWidth: 600,
      content: AddClipForm(
        full: full,
        initial: (
          bytes: forBoard.bytes,
          fileName: ClipTrim.fileName(_clip.at, 'mp3'),
          mime: 'audio/mpeg',
          duration: forBoard.length,
        ),
        onAdd: _addToBoard,
      ),
      actions: [
        AppButton(
          label: 'Back to the clip',
          variant: AppButtonVariant.secondary,
          onPressed: () => setState(() => _forBoard = null),
        ),
      ],
    );
  }
}
