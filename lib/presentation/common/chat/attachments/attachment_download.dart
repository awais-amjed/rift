import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/disk_file.dart';
import '../../confirm_dialog.dart';

export '../../../../logic/services/byte_format.dart' show humanSize;

/// Saves [bytes] to a user-chosen location. Shared by images + file cards.
///
/// If the chosen path already exists we ask before overwriting — some desktop
/// save dialogs (notably GTK on Linux) don't prompt on overwrite themselves.
Future<void> saveToDisk(
  BuildContext context,
  String suggestedName,
  Uint8List bytes,
) async {
  final location = await getSaveLocation(suggestedName: suggestedName);
  if (location == null) return;

  final path = location.path;
  if (await DiskFile.exists(path)) {
    if (!context.mounted) return;
    final replace = await showConfirmDialog(
      context: context,
      title: 'Replace file?',
      message:
          '"${DiskFile.name(path)}" already exists in that folder. '
          'Replace it?',
      confirmLabel: 'Replace',
      icon: Icons.save_as_rounded,
    );
    if (!replace) return;
  }

  await DiskFile.write(path, bytes);
  HelperMethods.showToast(title: 'Saved', description: suggestedName);
}
