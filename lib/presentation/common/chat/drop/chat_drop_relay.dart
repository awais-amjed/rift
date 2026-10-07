import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

/// A file handed to the composer — by the picker, or dropped on a chat pane —
/// not read yet: the composer decides whether it is small enough to hold.
///
/// The name travels beside the file rather than in it: off the web,
/// `XFile.fromData` ignores the name it is given, so a file wrapped from
/// bytes would arrive called "".
///
/// `temporary` marks a copy made to be sent rather than the person's own file
/// (`PendingAttachment.temporary`), which is deleted once it has gone.
typedef DroppedFile = ({
  String name,
  XFile file,
  int size,
  String? mimeType,
  bool temporary,
});

/// Carries files dropped anywhere on a chat pane to the composer at its foot.
///
/// The drop lands on the whole pane — aiming at a bar 46px tall is not how
/// anybody drags a picture in — but the files belong to the composer, which
/// owns the staged list and the checks on it. The composer claims the relay
/// while it can take files and releases it when it goes, so a pane whose
/// composer is gone or may not attach (read-only, waiting for a key, a member
/// without the permission) shows no "drop here" at all.
class ChatDropRelay {
  bool Function()? _accepts;
  ValueChanged<List<DroppedFile>>? _onFiles;

  /// Whether a drop here would go anywhere right now.
  bool get accepts => _accepts?.call() ?? false;

  void claim({
    required bool Function() accepts,
    required ValueChanged<List<DroppedFile>> onFiles,
  }) {
    _accepts = accepts;
    _onFiles = onFiles;
  }

  /// Lets go only if [onFiles] is still the claimant: a composer rebuilt for a
  /// new conversation claims before the old one's dispose releases.
  void release(ValueChanged<List<DroppedFile>> onFiles) {
    if (_onFiles != onFiles) return;
    _accepts = null;
    _onFiles = null;
  }

  void deliver(List<DroppedFile> files) {
    if (files.isEmpty || !accepts) return;
    _onFiles?.call(files);
  }
}

/// Puts a [ChatDropRelay] where the composer below it can find it.
class ChatDropScope extends InheritedWidget {
  final ChatDropRelay relay;

  const ChatDropScope({super.key, required this.relay, required super.child});

  static ChatDropRelay? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatDropScope>()?.relay;

  @override
  bool updateShouldNotify(ChatDropScope old) => old.relay != relay;
}
