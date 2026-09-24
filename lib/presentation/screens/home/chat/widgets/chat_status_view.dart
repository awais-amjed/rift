import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/centered_scroll_view.dart';
import '../../../../common/icon_tile.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Centered status panel for the non-ready chat states (waiting for the
/// channel key, load errors), with an optional retry button.
///
/// A state that resolves by itself says so with [listening] rather than a
/// Retry: offering a button implies the person is expected to press it, which
/// is what made waiting for a key read as broken. [detail] sits under it — the
/// people a key is waiting on.
class ChatStatusView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool showRetry;

  /// What is being waited for, drawn as a pill with the app's working dots.
  final String? listening;

  final Widget? detail;

  const ChatStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.showRetry = false,
    this.listening,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;

    return CenteredScrollView(
      padding: const EdgeInsets.all(24),
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconTile(
            icon: icon,
            color: themeState.accentBright,
            size: 56,
            radius: K.radiusCard,
            iconSize: 26,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: AppText.sectionTitle.copyWith(color: themeState.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.rowQuiet.copyWith(color: themeState.textTertiary),
          ),
          if (listening != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: themeState.bgHover,
                borderRadius: BorderRadius.circular(K.radiusPill),
                border: Border.all(color: themeState.borderElevated),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 9,
                children: [
                  LoadingDots(color: themeState.accentBright),
                  Text(
                    listening!,
                    style: AppText.meta.copyWith(
                      color: themeState.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (detail != null) ...[const SizedBox(height: 24), detail!],
          if (showRetry) ...[
            const SizedBox(height: 16),
            AppButton(
              label: 'Try again',
              variant: AppButtonVariant.secondary,
              onPressed: () => context.read<ChannelChatCubit>().retry(),
            ),
          ],
        ],
      ),
    );
  }
}
