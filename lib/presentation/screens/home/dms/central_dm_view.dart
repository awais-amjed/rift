import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import 'central_dm_chat_view.dart';

/// Home's content panel: the open central conversation, or the resting state.
///
/// The conversation list is not here — it lives in the sidebar column, where
/// a server's channels would be (see `CentralDmListPanel`). This panel is the
/// exact counterpart of a channel's chat, and holding only the conversation is
/// what makes the two tiers feel like the same app.
class CentralDmView extends StatelessWidget {
  const CentralDmView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CentralDmCubit>().state;
    if (state.openPeerId != null) return const CentralDmChatView();
    return _RestingState(status: state.status);
  }
}

class _RestingState extends StatelessWidget {
  final CentralDmStatus status;

  const _RestingState({required this.status});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    final (title, message) = switch (status) {
      CentralDmStatus.signedOut => (
        'Central DMs need an account',
        'Sign in under Settings → Cloud Backup to message people across '
            'servers.',
      ),
      CentralDmStatus.needsHandle => (
        'Pick a handle',
        'Claim a handle in the panel on the left so people can find you.',
      ),
      _ => (
        'Your central DMs',
        'Find someone by handle to start a conversation.',
      ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, size: 44, color: themeState.textQuaternary),
            const SizedBox(height: 12),
            Text(
              title,
              style: AppText.sectionTitle.copyWith(
                color: themeState.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: themeState.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
