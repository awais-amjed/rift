import 'package:flutter/material.dart';

import 'composer_notice.dart';

/// In the composer's place when a conversation could not be opened but this
/// device kept a copy of it.
///
/// The list above is still drawn, so this has to say what it is: the messages
/// saved here, not the conversation as it stands — something may have been
/// deleted or edited since. And sending has to wait, since nothing about the
/// conversation has been confirmed, so the retry sits where the send would.
class SavedCopyNotice extends StatelessWidget {
  final VoidCallback onRetry;

  const SavedCopyNotice({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ComposerNotice(
      icon: Icons.cloud_off_rounded,
      text:
          'Couldn’t load the latest messages. These are the ones saved on '
          'this device.',
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}
