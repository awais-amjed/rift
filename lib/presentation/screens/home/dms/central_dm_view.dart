import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../common/app_button.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../pane_toggles/pane_corner_toggles.dart';
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
    // No header here, and on Home the sidebar is where the conversation
    // list lives — so hidden, this corner is the only way back to it.
    return PaneCornerToggles.over(
      _RestingState(status: state.status),
      members: false,
    );
  }
}

class _RestingState extends StatelessWidget {
  final CentralDmStatus status;

  const _RestingState({required this.status});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;

    final (title, message) = switch (status) {
      CentralDmStatus.signedOut => (
        'Rift DMs need an account',
        'Sign in under Settings → Account & backup to message people across '
            'servers.',
      ),
      CentralDmStatus.needsHandle => (
        'Pick a handle',
        'Claim a handle in the panel on the left so people can find you.',
      ),
      // `ready` is answered by the friends page above, so this is a pass that
      // could not reach central. It used to read "Finding your account…" and
      // stay that way; the cubit now keeps asking, and says so.
      _ => (
        "Can't reach your Rift account",
        'Your Rift DMs load as soon as the account server answers. Rift keeps '
            'trying.',
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
            if (status == CentralDmStatus.error) ...[
              const SizedBox(height: 16),
              AppButton(
                label: 'Try again',
                variant: AppButtonVariant.secondary,
                onPressed: context.read<CentralDmCubit>().retryReady,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
