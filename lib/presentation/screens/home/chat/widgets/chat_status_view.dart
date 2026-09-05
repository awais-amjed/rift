import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/app_text.dart';

/// Centered status panel for the non-ready chat states (waiting for the
/// channel key, load errors), with an optional retry button.
class ChatStatusView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool showRetry;

  const ChatStatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.showRetry = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: themeState.textQuaternary),
            const SizedBox(height: 14),
            Text(
              title,
              style: AppText.sectionTitle.copyWith(
                color: themeState.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.rowQuiet.copyWith(color: themeState.textTertiary),
            ),
            if (showRetry) ...[
              const SizedBox(height: 16),
              AppButton(
                label: 'Retry',
                variant: AppButtonVariant.secondary,
                onPressed: () => context.read<ChannelChatCubit>().retry(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
