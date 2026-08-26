import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_text.dart';
import 'central_dm_chat_view.dart';
import 'central_friends_view.dart';

/// Home's content panel: the open central conversation, or your friends.
///
/// The conversation list is not here — it lives in the sidebar column, where
/// a server's channels would be (see `CentralDmListPanel`). This panel is the
/// exact counterpart of a channel's chat, and holding only the conversation is
/// what makes the two tiers feel like the same app.
///
/// With nothing open it shows the friends page rather than a line of copy.
/// Home is a tier you stand on, and a tier whose resting state is an
/// apology for being empty is one people leave. The signed-out and
/// no-handle states keep theirs: there is genuinely nothing behind them yet.
class CentralDmView extends StatelessWidget {
  const CentralDmView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<CentralDmCubit>().state;
    if (state.openPeerId != null) return const CentralDmChatView();
    if (state.status == CentralDmStatus.ready) {
      return const CentralFriendsView();
    }
    return _RestingState(status: state.status);
  }
}

class _RestingState extends StatelessWidget {
  final CentralDmStatus status;

  const _RestingState({required this.status});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    // Where the conversation list is depends on how much window there is, and
    // copy that says "on the left" is simply wrong on a phone, where the panel
    // it points at is a drawer that has to be opened first — the one thing the
    // reader needs to be told.
    final listLocation = context.layoutMode.sidebarIsOverlay
        ? 'in the menu'
        : 'in the panel on the left';

    final (title, message) = switch (status) {
      CentralDmStatus.signedOut => (
        'Central DMs need an account',
        'Sign in under Settings → Cloud Backup to message people across '
            'servers.',
      ),
      CentralDmStatus.needsHandle => (
        'Pick a handle',
        'Claim a handle $listLocation so people can find you.',
      ),
      // Reached only while a readiness pass is still running, or after one
      // failed — `ready` is answered by the friends page above.
      _ => ('Your central DMs', 'Finding your account…'),
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
