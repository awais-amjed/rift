import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import 'attachment_file_card.dart';
import 'attachment_image_thumb.dart';
import 'attachment_loader.dart';
import 'attachment_plain_badge.dart';
import 'audio_message_player.dart';

/// Renders a message's decrypted attachments beneath its text: images as
/// rounded thumbnails, audio inline players, and everything else as a download
/// card. Bytes are fetched lazily via [loader] (cache-first).
class MessageAttachments extends StatelessWidget {
  final List<Attachment> attachments;
  final AttachmentLoader loader;
  const MessageAttachments({
    super.key,
    required this.attachments,
    required this.loader,
  });

  Widget _body(Attachment a) => switch (a.kind) {
    AttachmentKind.image => AttachmentImageThumb(
      key: ValueKey(a.id),
      attachment: a,
      loader: loader,
    ),
    AttachmentKind.audio => AudioMessagePlayer(
      key: ValueKey(a.id),
      attachment: a,
      loader: loader,
    ),
    AttachmentKind.file => AttachmentFileCard(
      key: ValueKey(a.id),
      attachment: a,
      loader: loader,
    ),
  };

  /// A file sent unencrypted, with the pill that says so under it.
  Widget _plain(Attachment a) => Column(
    key: ValueKey('plain-${a.id}'),
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [_body(a), const AttachmentPlainBadge()],
  );

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
          for (final a in attachments) a.isEncrypted ? _body(a) : _plain(a),
        ],
      ),
    );
  }
}
