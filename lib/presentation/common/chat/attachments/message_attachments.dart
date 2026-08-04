import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'attachment_file_card.dart';
import 'attachment_image_thumb.dart';
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
          // Keyed by attachment so each keeps its own state — an in-flight
          // fetch, a playback position — if the message's list ever shifts.
          for (final a in attachments)
            switch (a.kind) {
              AttachmentKind.image => AttachmentImageThumb(
                key: ValueKey(a.id),
                attachment: a,
                loader: loader,
                themeState: themeState,
              ),
              AttachmentKind.audio => AudioMessagePlayer(
                key: ValueKey(a.id),
                attachment: a,
                loader: loader,
                themeState: themeState,
              ),
              AttachmentKind.file => AttachmentFileCard(
                key: ValueKey(a.id),
                attachment: a,
                loader: loader,
                themeState: themeState,
              ),
            },
        ],
      ),
    );
  }
}
