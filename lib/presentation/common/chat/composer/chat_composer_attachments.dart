part of 'chat_composer.dart';

/// Picking files and deciding whether they may be staged.
///
/// The size check lives here rather than at the upload, so an oversized file
/// is refused with a sentence at the moment it is chosen — instead of after it
/// has been read, encrypted, and pushed at a bucket that answers 413. The
/// bucket's own `file_size_limit` is still the enforcement; this is the
/// courtesy.
mixin _ComposerAttachmentsMixin on State<ChatComposer> {
  /// Implemented by the State class — the composer's own list, which the bar
  /// renders and the send drains.
  List<PendingAttachment> get _staged;

  /// Implemented by the recording mixin.
  bool get _isRecording;

  Future<void> _pickFiles() async {
    if (!widget.enabled) return;
    try {
      for (final file in await _chooseFiles()) {
        await _stage((
          name: file.name,
          file: file,
          size: await file.length(),
          mimeType: file.mimeType,
          // file_picker hands a phone's pick over as a copy in the app's
          // cache; it is the app's to delete.
          temporary: HostPlatform.isMobile,
        ));
      }
      if (mounted) setState(() {});
    } catch (e) {
      HelperMethods.printDebug('[Composer] file pick failed: $e');
      HelperMethods.showError(error: "Couldn't attach that file.");
    }
  }

  /// The system's picker, unread.
  ///
  /// Not file_selector's on a phone: its Android side reads every picked file
  /// into memory and sends the bytes across the channel, which a big video
  /// cannot survive. file_picker copies it to a cache file there instead,
  /// natively and a piece at a time, and hands back the path.
  Future<List<XFile>> _chooseFiles() async {
    if (!HostPlatform.isMobile) return openFiles();
    final picked = await FilePicker.pickFiles();
    return [for (final file in picked) file.xFile];
  }

  /// Files dragged onto the chat pane, handed over by its `ChatDropZone`.
  ///
  /// The same road as the picker, so a dropped file meets the same size and
  /// count checks — dropping is only a faster way to choose.
  Future<void> _onDropped(List<DroppedFile> files) async {
    try {
      for (final file in files) {
        await _stage(file);
      }
      if (mounted) setState(() {});
    } catch (e) {
      HelperMethods.printDebug('[Composer] dropped file failed: $e');
      HelperMethods.showError(error: "Couldn't attach that file.");
    }
  }

  /// Whether a drop on the pane would be taken: the same conditions that
  /// show the attach button.
  bool get _takesDrops =>
      mounted && widget.enabled && widget.canAttach && !_isRecording;

  ChatDropRelay? _dropRelay;

  /// Called from `didChangeDependencies`: the pane's relay, claimed while
  /// this composer is the one under it.
  void _claimDropRelay() {
    final relay = ChatDropScope.maybeOf(context);
    if (relay == _dropRelay) return;
    _dropRelay?.release(_onDropped);
    _dropRelay = relay?..claim(accepts: () => _takesDrops, onFiles: _onDropped);
  }

  void _releaseDropRelay() => _dropRelay?.release(_onDropped);

  /// Adds [file] to the staged list if it fits. One rejected file doesn't
  /// abandon the rest of the selection, so this refuses quietly past the
  /// toast; the caller rebuilds once for the lot.
  Future<void> _stage(DroppedFile file) async {
    if (!_accepts(name: file.name, bytes: file.size)) {
      if (file.temporary) await discardCopy(file.file);
      return;
    }
    _staged.add(
      await AttachmentStaging.stage(
        file: file.file,
        size: file.size,
        name: file.name,
        mimeType: file.mimeType,
        temporary: file.temporary,
      ),
    );
  }

  /// True when the file fits; shows the reason and returns false when it
  /// doesn't.
  bool _accepts({required String name, required int bytes}) {
    final rejection = AttachmentStaging.rejectionFor(
      name: name,
      bytes: bytes,
      maxBytes: widget.maxAttachmentBytes,
      alreadyStaged: _staged.length,
      remainingBytes: widget.remainingStorageBytes,
      stagedBytes: _staged.fold(0, (sum, a) => sum + a.size),
    );
    if (rejection == null) return true;
    HelperMethods.showError(error: rejection);
    return false;
  }

  void _removeStaged(int index) {
    final removed = _staged[index];
    setState(() => _staged.removeAt(index));
    unawaited(AttachmentStaging.discard([removed]));
  }

  /// Switch a staged file between encrypted and unencrypted.
  void _togglePlain(int index) {
    setState(() {
      final file = _staged[index];
      _staged[index] = file.copyWith(plain: !file.plain);
    });
  }
}
