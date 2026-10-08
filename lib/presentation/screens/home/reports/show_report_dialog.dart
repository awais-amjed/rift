import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/apis/moderation_api.dart';
import '../../../../data/classes/chat_message.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../../common/app_modal.dart';
import 'report_dialog.dart';

/// Report a channel message on the selected server.
///
/// The disclosure is the part a reporter would want to know and could not
/// otherwise find out: who sees the report, and that the words stay sealed —
/// a moderator's own app opens them.
Future<void> showReportMessageDialog(
  BuildContext context,
  ChatMessage message,
) {
  final moderation = ModerationApi(session: context.read<SessionRepository>());
  final id = int.tryParse(message.id);
  if (id == null) return Future.value();
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    build: (_) => ReportDialog(
      title: 'Report message',
      subtitle: 'From ${message.authorName}',
      disclosure: message.isEncrypted
          ? '${message.authorName} isn\'t told who reported it. Moderators '
                'see your name and open the message with their own key — the '
                'server never sees what it says.'
          // A webhook's or a bot's words were never sealed, so the promise
          // above would be false here.
          : '${message.authorName} isn\'t told who reported it. Moderators '
                'see your name. This message wasn\'t end-to-end encrypted, '
                'so they read it as posted.',
      onSend: (reason, note) =>
          moderation.reportMessage(messageId: id, reason: reason, note: note),
    ),
  );
}

/// Report a member of the selected server — from their profile, or from a DM,
/// whose words no moderator could open.
Future<void> showReportMemberDialog(
  BuildContext context, {
  required String userId,
  required String displayName,
}) {
  final moderation = ModerationApi(session: context.read<SessionRepository>());
  return showCustomDialog(
    context: context,
    barrierDismissible: true,
    build: (_) => ReportDialog(
      title: 'Report $displayName',
      subtitle: 'To this server\'s moderators',
      disclosure:
          '$displayName isn\'t told who reported them. Moderators see your '
          'name and what you write here. They can\'t read your DMs, so say '
          'what happened.',
      onSend: (reason, note) =>
          moderation.reportMember(targetId: userId, reason: reason, note: note),
    ),
  );
}
