import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/custom_colors.dart';
import '../theme/theme_context.dart';

/// What a [MessageBanner] is saying — which sets its colour and icon.
///
/// `caution` is amber: something to know before going on, not something
/// that went wrong. Every error in the app goes through `error`; a bare red
/// line of text is not a second way to say it.
enum MessageBannerKind { caution, success, error }

/// Tinted inline banner carrying one sentence of feedback or caution.
///
/// Only the icon and the wash are coloured; the sentence itself stays body
/// grey. Colouring the text too turns a one-line warning into a block of red
/// that reads as far more alarming than what it usually says.
class MessageBanner extends StatelessWidget {
  final String message;
  final MessageBannerKind kind;

  const MessageBanner({super.key, required this.message, required this.kind});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (kind) {
      MessageBannerKind.caution => (CustomColors.warning, Icons.info_outlined),
      MessageBannerKind.success => (
        CustomColors.success,
        Icons.check_circle_outlined,
      ),
      MessageBannerKind.error => (CustomColors.error, Icons.error_outlined),
    };

    final themeState = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        // Top-aligned so the icon stays beside the first line rather than
        // drifting to the middle of a message that wraps.
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(icon, size: 16, color: themeState.statusInk(color)),
          Expanded(
            child: Text(
              message,
              style: AppText.secondary.copyWith(
                height: 1.5,
                color: themeState.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
