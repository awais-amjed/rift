part of 'chat_composer.dart';

/// The composer's voice-note half: hold to record, stop to stage it as an
/// audio attachment.
///
/// Split out because it is the only part of the composer that owns a device.
/// A microphone has permissions, a timer, and three ways to end — stopped,
/// cancelled, or failed — and none of that has anything to say about typing.
/// `on _ComposerAttachmentsMixin` rather than re-declaring `_accepts`: a
/// private member declared abstract in one mixin and implemented in another
/// trips `unused_element`, because the analyzer resolves the call to the
/// declaration and never sees the body (CODE_STYLE §5). Depending on the mixin
/// that has it avoids the whole question.
mixin _ComposerRecordingMixin
    on State<ChatComposer>, _ComposerAttachmentsMixin {
  /// Owned here, not by the State class: a microphone, whether it is running,
  /// how long for, and the ticker that says so are one thing, and the composer
  /// has nothing to say about any of them.
  final VoiceNoteRecorder _recorder = VoiceNoteRecorder();
  bool _isRecording = false;
  Duration _elapsed = Duration.zero;
  Timer? _recordTimer;

  /// Implemented by the State class, which owns the staged list this reads.
  bool get _atAttachmentLimit;

  void _disposeRecording() {
    _recordTimer?.cancel();
    _recorder.dispose();
  }

  Future<void> _startRecording() async {
    if (!widget.enabled || _isRecording || _atAttachmentLimit) return;
    try {
      if (!await _recorder.hasPermission()) {
        HelperMethods.showError(error: 'Microphone permission denied.');
        return;
      }
      await _recorder.start();
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _elapsed = Duration.zero;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
      });
    } catch (e) {
      HelperMethods.printDebug('[Composer] record start failed: $e');
      HelperMethods.showError(
        error: "Couldn't start recording — is a microphone available?",
      );
    }
  }

  /// Stop and stage the recording as an audio attachment.
  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final durationMs = _elapsed.inMilliseconds;
    try {
      final note = await _recorder.stop();
      if (!mounted) return;
      // A long enough recording outgrows the cap the same way a picked file
      // does, and finding that out at upload time would lose the take.
      if (note != null &&
          !_accepts(name: 'That recording', bytes: note.bytes.length)) {
        setState(() => _isRecording = false);
        return;
      }
      setState(() {
        _isRecording = false;
        if (note != null) {
          _staged.add(
            PendingAttachment(
              bytes: note.bytes,
              name: note.name,
              mime: note.mime,
              kind: AttachmentKind.audio,
              durationMs: durationMs,
            ),
          );
        }
      });
    } catch (e) {
      HelperMethods.printDebug('[Composer] reading recording failed: $e');
      if (mounted) setState(() => _isRecording = false);
      HelperMethods.showError(error: "Couldn't save the recording.");
    }
  }

  /// Discard the in-progress recording.
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() => _isRecording = false);
  }
}
