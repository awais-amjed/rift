import 'package:flutter/material.dart';

import '../../../../../../data/classes/webhook.dart';
import '../../../../../common/loading_dots.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import 'webhook_row.dart';

/// The webhooks already posting into a channel — or the reason there are none
/// on screen.
///
/// Three states in one place because they are one answer to one question, and
/// splitting "still asking" from "asked, none" across two widgets is how a
/// dialog ends up flashing *No webhooks yet* before its first load returns.
class WebhookList extends StatelessWidget {
  final List<Webhook> webhooks;
  final bool isLoading;
  final ValueChanged<Webhook> onDelete;

  const WebhookList({
    super.key,
    required this.webhooks,
    required this.isLoading,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: LoadingDots(color: themeState.textTertiary, dotSize: 4),
        ),
      );
    }

    if (webhooks.isEmpty) {
      return Text(
        'No webhooks yet.',
        style: AppText.meta.copyWith(color: themeState.textTertiary),
      );
    }

    // Flexible rather than Expanded: the dialog sizes to its content until it
    // runs out of room, and only then does this scroll.
    return Flexible(
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: webhooks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => WebhookRow(
          webhook: webhooks[i],

          onDelete: () => onDelete(webhooks[i]),
        ),
      ),
    );
  }
}
