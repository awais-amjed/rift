import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/enums/auth_status.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../common/app_button.dart';
import '../../common/canvas_backdrop.dart';
import '../../common/centered_scroll_view.dart';
import '../../common/feature_header.dart';
import '../../common/message_banner.dart';
import '../onboarding/widgets/onboarding_footer.dart';

/// Shown when secure storage could not be read at start
/// (`AuthStatus.unreadable`): a locked keyring, a keystore that failed.
///
/// Not onboarding. A vault is very likely there, and onboarding would offer
/// to make a new identity over it — which once happened, on Linux, to someone
/// whose keyring had not unlocked yet.
class VaultUnreadableScreen extends StatelessWidget {
  const VaultUnreadableScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final busy = context.select(
      (VaultCubit c) => c.state.status != AuthStatus.unreadable,
    );
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
                  icon: Icons.lock_outline_rounded,
                  title: "Rift can't read your keys",
                  subtitle:
                      "This device's secure storage did not answer. Your "
                      'vault has not been changed.',
                ),
                const SizedBox(height: 20),
                const MessageBanner(
                  message:
                      'If your system keyring or password manager is locked, '
                      'unlock it, then try again. Restarting the device can '
                      'help too.',
                  kind: MessageBannerKind.caution,
                ),
                const SizedBox(height: 20),
                OnboardingFooter(
                  primary: AppButton(
                    label: 'Try again',
                    isLoading: busy,
                    onPressed: busy
                        ? null
                        : () => context.read<VaultCubit>().checkVaultStatus(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
