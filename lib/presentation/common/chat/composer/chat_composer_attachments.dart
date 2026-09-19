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

  Future<void> _pickFiles() async {
    if (!widget.enabled) return;
    try {
      final files = await openFiles();
      if (files.isEmpty) return;
      for (final file in files) {
        final bytes = await file.readAsBytes();
        // One rejected file doesn't abandon the rest of the selection.
        if (!_accepts(name: file.name, bytes: bytes.length)) continue;
        _staged.add(
          await AttachmentStaging.stage(
            bytes: bytes,
            name: file.name,
            mimeType: file.mimeType,
          ),
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      HelperMethods.printDebug('[Composer] file pick failed: $e');
      HelperMethods.showError(error: "Couldn't attach that file.");
    }
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
      stagedBytes: _staged.fold(0, (sum, a) => sum + a.bytes.length),
    );
    if (rejection == null) return true;
    HelperMethods.showError(error: rejection);
    return false;
  }

  void _removeStaged(int index) {
    setState(() => _staged.removeAt(index));
  }
}
