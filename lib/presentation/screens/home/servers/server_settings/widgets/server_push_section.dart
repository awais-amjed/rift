import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_switch.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/no_central_account.dart';
import '../../../../../theme/app_text.dart';
import '../../../../settings/widgets/section_title.dart';

/// Whether this server may wake its members' phones, in the settings dialog.
///
/// Beneath Discovery rather than beside it because it is the same kind of
/// setting: both are this server asking central for something it cannot do
/// alone. A listing is how strangers find the server; a relay credential is
/// how it reaches a phone that has stopped running Rift — an FCM token is
/// scoped to the Firebase project the app was built against, so nobody but
/// Rift can wake a Rift install, and an operator cannot be handed those keys.
class ServerPushSection extends StatelessWidget {
  /// Whether push is on, or null while the server is still being asked.
  final bool? enabled;

  /// Whether the admin has a central account. Without one there is nothing to
  /// enrol the credential against.
  final bool signedIn;

  final ValueChanged<bool> onChanged;
  final ThemeState themeState;
  final bool interactive;

  const ServerPushSection({
    super.key,
    required this.enabled,
    required this.signedIn,
    required this.onChanged,
    required this.themeState,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(label: 'Notifications', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          'Wake members’ phones for messages that arrive while Rift is '
          'closed. Without this, a phone only learns about a message the next '
          'time someone opens the app.',
          style: AppText.secondary.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 14),
        if (!signedIn)
          const NoCentralAccount(
            need:
                'Only Rift can wake a Rift install, so this server has to ask '
                'central to pass the ping along — which needs a Rift account '
                'to issue the permission to, and to take it back with.',
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Send push notifications',
                  style: AppText.row.copyWith(color: themeState.textPrimary),
                ),
              ),
              AppSwitch(
                value: enabled ?? false,
                onChanged: interactive && enabled != null ? onChanged : null,
              ),
            ],
          ),
          if (enabled == true) ...[
            const SizedBox(height: 14),
            const HintCard(
              icon: Icons.notifications_active_outlined,
              text:
                  'The ping itself carries nothing — not the sender, not the '
                  'text, not which channel. Central learns that a device was '
                  'pinged and when, and that is all it can learn: the phone '
                  'holds the keys and reads the message itself once awake.',
            ),
          ],
        ],
      ],
    );
  }
}
