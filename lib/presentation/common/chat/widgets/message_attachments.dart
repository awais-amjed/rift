import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import 'attachment_loader.dart';
import 'audio_message_player.dart';

/// Renders a message's decrypted attachments beneath its text: images as
/// rounded thumbnails, audio inline players, and everything else as a download
/// card. Bytes are fetched lazily via [loader] (cache-first).
class MessageAttachments extends StatelessWidget {
  final List<Attachment> attachments;
  final AttachmentLoader loader;
  final ThemeState themeState;

  const MessageAttachments({
    super.key,
    required this.attachments,
    required this.loader,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final a in attachments)
            switch (a.kind) {
              AttachmentKind.image =>
                _ImageThumb(attachment: a, loader: loader, themeState: themeState),
              AttachmentKind.audio => AudioMessagePlayer(
                  attachment: a,
                  loader: loader,
                  themeState: themeState,
                ),
              AttachmentKind.file =>
                _FileCard(attachment: a, loader: loader, themeState: themeState),
            },
        ],
      ),
    );
  }
}

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
    final replace = await _confirmReplace(context, file.uri.pathSegments.last);
    if (replace != true) return;
  }

  await file.writeAsBytes(bytes);
  HelperMethods.showToast(title: 'Saved', description: suggestedName);
}

Future<bool?> _confirmReplace(BuildContext context, String name) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Replace file?'),
      content: Text('"$name" already exists. Replace it?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
}

class _ImageThumb extends StatelessWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  final ThemeState themeState;

  const _ImageThumb({
    required this.attachment,
    required this.loader,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: loader(attachment),
      builder: (context, snap) {
        final size = 220.0;
        Widget child;
        if (snap.connectionState != ConnectionState.done) {
          child = Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: themeState.primary,
              ),
            ),
          );
        } else if (snap.data == null) {
          child = Center(
            child: Icon(Icons.broken_image_outlined,
                color: themeState.textQuaternary),
          );
        } else {
          final bytes = snap.data!;
          return GestureDetector(
            onTap: () => _openFull(context, bytes),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: size, maxHeight: size),
                child: Image.memory(bytes, fit: BoxFit.cover),
              ),
            ),
          );
        }
        return Container(
          width: size,
          height: 140,
          decoration: BoxDecoration(
            color: themeState.bgTertiary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: child,
        );
      },
    );
  }

  void _openFull(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: Image.memory(bytes)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: Colors.white),
                    tooltip: 'Save',
                    onPressed: () => saveToDisk(context, attachment.name, bytes),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileCard extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  final ThemeState themeState;

  const _FileCard({
    required this.attachment,
    required this.loader,
    required this.themeState,
  });

  @override
  State<_FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<_FileCard> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bytes = await widget.loader(widget.attachment);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) {
      HelperMethods.showError(error: "Couldn't download that file.");
      return;
    }
    if (!mounted) return;
    await saveToDisk(context, widget.attachment.name, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeState;
    return InkWell(
      onTap: _download,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.bgTertiary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.borderPrimary),
        ),
        child: Row(
          children: [
            Icon(Icons.insert_drive_file_outlined,
                size: 28, color: theme.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    humanSize(widget.attachment.size),
                    style: TextStyle(fontSize: 11, color: theme.textQuaternary),
                  ),
                ],
              ),
            ),
            _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primary,
                    ),
                  )
                : Icon(Icons.download_rounded, size: 20, color: theme.textTertiary),
          ],
        ),
      ),
    );
  }
}
