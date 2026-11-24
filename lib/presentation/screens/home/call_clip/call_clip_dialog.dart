import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/classes/call_clip_audio.dart';
import '../../../../data/constants.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/clip_history/clip_history_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/call_clip/clip_preview.dart';
import '../../../../logic/services/call_clip/clip_trim.dart';
import '../../../../logic/services/clock_time.dart';
import '../../../../src/rust/api/call_clip.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/chat/attachments/attachment_download.dart';
import '../../../common/confirm_dialog.dart';
import '../../../common/server_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../servers/manage/panels/soundboard/add_clip_form.dart';
import 'widgets/clip_actions.dart';
import 'widgets/clip_play_line.dart';
import 'widgets/clip_preview_button.dart';
import 'widgets/clip_trim_handles.dart';
import 'widgets/clip_waveform.dart';

/// Over the widget budget and one job: the trim view, its two endings (Save,
/// Add to soundboard) sharing the cut.
///
/// A clip of the call, to trim and then save as a WAV or put on the call's
/// soundboard as an MP3 (CALLS.md, "Clipping a call"). Opened by
/// [CallClipOpener] in the call's server scope, with its own copy of the
/// audio: the ring keeps running, and the call can end under it. Or opened
/// again from the clips kept on this device (`openStoredClip`), in the scope
/// of the server it was clipped on, while that is still on the list.
class CallClipDialog extends StatefulWidget {
  final CallClipAudio clip;

  /// Whether it came from a DM call, as it was when clipped: a DM has no
  /// soundboard, whatever server it is on.
  final bool fromDmCall;

  /// The server it was clipped on, whose soundboard Add puts it on; null
  /// when that is not on the list any more. Add is offered only inside that
  /// server's scope: opened anywhere else, the soundboard read here is
  /// another server's.
  final String? serverId;

  const CallClipDialog({
    super.key,
    required this.clip,
    required this.fromDmCall,
    required this.serverId,
  });

  /// Whether Add to soundboard is offered: to somebody who may manage the
  /// soundboard, for a clip from a channel's call, inside the scope of the
  /// server it was clipped on ([scopeServerId]) — never another's, which is
  /// whose soundboard would be read there.
  static bool offersAdd({
    required bool fromDmCall,
    required String? clipServerId,
    required String? scopeServerId,
    required bool canManage,
  }) =>
      canManage &&
      !fromDmCall &&
      clipServerId != null &&
      clipServerId == scopeServerId;

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

  /// Playing the clip from the line over the waveform, on the call's output.
  late final ClipPreview _preview = ClipPreview(
    clip: widget.clip,
    outputId: () => context.read<AppCubit>().state.callOutputId,
  );
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
    _preview.head.value = _start;
    // Not a focus shortcut: the app's KeyboardDismisser clears focus on every
    // click, which would leave Space dead after the first one.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _preview.dispose();
    super.dispose();
  }

  /// Space plays and pauses, while this view is the one on top: not under a
  /// dialog it opened, and not on the soundboard's form, which is typed into.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.space ||
        !mounted ||
        _forBoard != null ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    _preview.toggle();
    return true;
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

  /// Drops the clip from the ones this device keeps, and closes the view: a
  /// clip saved or put on a soundboard stays where it went.
  Future<void> _delete() async {
    final history = context.read<ClipHistoryCubit>();
    final navigator = Navigator.of(context);
    final sure = await showConfirmDialog(
      context: context,
      title: 'Delete this clip?',
      message:
          'It goes from the clips kept on this device. A copy you saved or '
          'put on a soundboard stays.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!sure || !mounted) return;
    await history.deleteTakenAt(_clip.at);
    navigator.pop();
  }

  Future<void> _encodeForBoard() async {
    _preview.pause();
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
    final serverId = ServerScope.idOf(context);
    final canManage = context.select<ServerCubit, bool>(
      (cubit) =>
          cubit.state
              .permissionsOn(serverId)
              ?.can(ServerPermission.manageSoundboard) ??
          false,
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
      // Room for Delete, Add and Save on one line beside Play.
      maxWidth: 680,
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
                ClipPlayLine(head: _preview.head),
                ClipTrimHandles(
                  start: _start,
                  end: _end,
                  minGap: total > _shortest
                      ? _shortest.inMicroseconds / total.inMicroseconds
                      : 1,
                  onChanged: (start, end) {
                    _preview.select(start, end);
                    setState(() {
                      _start = start;
                      _end = end;
                    });
                  },
                  onSeek: _preview.seek,
                  onScrubStart: _preview.beginScrub,
                  onScrubEnd: _preview.endScrub,
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
              ClipPreviewButton(preview: _preview),
              const SizedBox(width: 10),
              Expanded(
                child: ClipActions(
                  wavBytes: ClipTrim.wavBytes(_length),
                  mp3Bytes: ClipTrim.mp3Bytes(_length, CallClipDialog.kbps),
                  saving: _saving,
                  adding: _encoding,
                  onSave: _save,
                  onDelete: _delete,
                  onAdd:
                      CallClipDialog.offersAdd(
                        fromDmCall: widget.fromDmCall,
                        clipServerId: widget.serverId,
                        scopeServerId: serverId,
                        canManage: canManage,
                      )
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
