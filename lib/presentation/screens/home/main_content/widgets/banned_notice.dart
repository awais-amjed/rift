import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// Shown in place of a server's content when that server has banned or
/// kicked you.
///
/// It exists because the alternative is silence. A ban makes `app.server_id()`
/// null, so every policy on the server stops matching and every read comes
/// back empty — no channels, no members, no messages, and no error either. The
/// app looks broken rather than closed, and the one person who most needs to
/// know what happened is the only one nobody tells.
///
/// Deliberately plain about what it does and doesn't mean: the account is
/// fine, this server is not. There is no retry button because nothing the
/// person can do from this side changes it.
///
/// A kick is the same lock-out with a way back — a new invite from somebody
/// there — and says so, because "banned" would tell them not to bother.
class BannedNotice extends StatelessWidget {
  /// The server that banned them, named so it reads as one server rather than
  /// the app having died.
  final String serverName;

  /// Kicked rather than banned (`users.kicked_at`).
  final bool kicked;

  const BannedNotice({
    super.key,
    required this.serverName,
    this.kicked = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CustomColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(K.radiusCard),
              ),
              child: Icon(
                kicked ? Icons.logout_rounded : Icons.gavel_rounded,
                size: 32,
                color: CustomColors.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              kicked
                  ? 'You were removed from $serverName'
                  : 'You were banned from $serverName',
              textAlign: TextAlign.center,
              style: AppText.pageTitle.copyWith(color: themeState.textPrimary),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                kicked
                    ? 'Its channels, members and messages are closed to you '
                          'for now. A new invite from somebody there brings '
                          'you back, as yourself.'
                    : 'Its channels, members and messages are closed to you. '
                          'Only an admin there can lift this — if one does, '
                          'the app comes back on its own.',
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: themeState.textTertiary),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                'Your account and your other servers are unaffected.',
                textAlign: TextAlign.center,
                style: AppText.rowQuiet.copyWith(
                  color: themeState.textQuaternary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
