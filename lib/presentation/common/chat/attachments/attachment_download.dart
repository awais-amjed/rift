import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/attachment_loader.dart';
import '../../../../logic/services/file_save/save_target.dart';
import '../../app_toast.dart';
import '../../confirm_dialog.dart';

export '../../../../logic/services/byte_format.dart' show humanSize;

/// Save [attachment] where the person chooses, downloading and opening it a
/// piece at a time so a file bigger than memory still saves. [onProgress]
/// hears how far it has got, 0 to 1.
Future<void> saveAttachment(
  BuildContext context,
  AttachmentLoader loader,
  Attachment attachment, {
  ValueChanged<double>? onProgress,
}) async {
  final sink = await _choose(context, attachment.name);
  if (sink == null) return;
  // A report per chunk is a redraw per megabyte; a whole percent is plenty.
  var shown = -1;
  final result = await loader.save(
    attachment,
    sink,
    onProgress: onProgress == null
        ? null
        : (done, total) {
            final percent = total == 0 ? 100 : done * 100 ~/ total;
            if (percent == shown) return;
            shown = percent;
            onProgress(percent / 100);
          },
  );
  if (!result.success) {
    HelperMethods.showError(error: "Couldn't download that file.");
    return;
  }
  if (sink.saved) _saved(sink, attachment.name);
}

/// Save [bytes] already in hand — a picture open in the viewer — the same
/// way.
Future<void> saveToDisk(
  BuildContext context,
  String suggestedName,
  Uint8List bytes,
) async {
  final sink = await _choose(context, suggestedName);
  if (sink == null) return;
  await sink.add(bytes);
  await sink.close();
  if (sink.saved) _saved(sink, suggestedName);
}

/// Says the file is saved, with a way to it and its folder where the app
/// knows where it went.
/// Longer than a plain toast when there is a button on it to reach for.
void _saved(SaveSink sink, String name) {
  final location = sink.location;
  HelperMethods.showToast(
    title: 'Saved',
    description: name,
    autoCloseDuration: location == null
        ? const Duration(seconds: 3)
        : const Duration(seconds: 6),
    actions: [
      if (location != null) ...[
        ToastAction(
          label: 'Open',
          primary: true,
          onPressed: () async {
            if (!await openSavedFile(location)) {
              HelperMethods.showError(error: "Couldn't open that file.");
            }
          },
        ),
        ToastAction(
          label: 'Show in folder',
          onPressed: () async {
            if (!await showInFolder(location)) {
              HelperMethods.showError(error: "Couldn't open that folder.");
            }
          },
        ),
      ],
    ],
  );
}

/// Where to save [name], asking before replacing a file — some desktop save
/// dialogs (notably GTK on Linux) don't ask on overwrite themselves.
Future<SaveSink?> _choose(BuildContext context, String name) =>
    chooseSaveTarget(
      name,
      confirmReplace: (existing) async {
        if (!context.mounted) return false;
        return showConfirmDialog(
          context: context,
          title: 'Replace file?',
          message: '"$existing" already exists in that folder. Replace it?',
          confirmLabel: 'Replace',
          icon: Icons.save_as_rounded,
        );
      },
    );
