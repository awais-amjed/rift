import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../common/app_button.dart';
import '../../common/button_footer.dart';
import '../../common/canvas_backdrop.dart';
import '../../common/centered_scroll_view.dart';
import '../../common/feature_header.dart';
import '../../common/message_banner.dart';
import 'widgets/recovery_key_acknowledgement.dart';
import 'widgets/recovery_key_card.dart';

/// Shown once, immediately after a vault is created, and not skippable.
///
/// **Why it blocks.** The key is generated on the device and never sent
/// anywhere, so this screen is the only moment it exists outside a wrapped
/// blob. Offering it as a dismissible notice, or a thing to find in settings
/// later, would mean most people never see it — and the population that most
/// needs a recovery key is exactly the population that does not go looking for
/// one while they still remember their password.
///
class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen({super.key});

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultCubit>();
    final key = vault.state.pendingRecoveryKey;

    // Acknowledged on another route, or never issued. The router sends us
    // away; render nothing rather than a screen with a blank key on it.
    if (key == null) return const SizedBox.shrink();

    return Scaffold(
      body: CanvasBackdrop(
        glowCenter: const Alignment(0, -0.6),
        glowRadius: 0.9,
        glowOpacity: 0.13,
        child: SafeArea(
          child: CenteredScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            maxWidth: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FeatureHeader(
                  icon: Icons.vpn_key_rounded,
                  title: 'Your recovery key',
                  subtitle:
                      'Write this down and keep it somewhere safe. It is '
                      'shown once and never again.',
                ),
                const SizedBox(height: 28),
                RecoveryKeyCard(recoveryKey: key),
                const SizedBox(height: 20),
                const MessageBanner(
                  message:
                      'If you forget your password, this key is the only '
                      'way back to your messages and servers. Rift cannot '
                      'reset it for you — your data is encrypted on this '
                      'device, and nobody else holds a key that opens it. '
                      'Lose both and it is gone.',
                  kind: MessageBannerKind.caution,
                ),
                const SizedBox(height: 20),
                RecoveryKeyAcknowledgement(
                  value: _acknowledged,

                  onChanged: (v) => setState(() => _acknowledged = v),
                ),
                const SizedBox(height: 20),
                ButtonFooter(
                  buttons: [
                    AppButton(
                      label: 'Continue',
                      onPressed: _acknowledged
                          ? () => context
                                .read<VaultCubit>()
                                .acknowledgeRecoveryKey()
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
