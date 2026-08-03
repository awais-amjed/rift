import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../../logic/helper_methods.dart';
import '../../confirm_dialog.dart';

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

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

  final file = File(location.path);
  if (await file.exists()) {
    if (!context.mounted) return;
    final replace = await showConfirmDialog(
      context: context,
      title: 'Replace file?',
      message:
          '"${file.uri.pathSegments.last}" already exists in that folder. '
          'Replace it?',
      confirmLabel: 'Replace',
      icon: Icons.save_as_rounded,
    );
    if (!replace) return;
  }

  await file.writeAsBytes(bytes);
  HelperMethods.showToast(title: 'Saved', description: suggestedName);
}
