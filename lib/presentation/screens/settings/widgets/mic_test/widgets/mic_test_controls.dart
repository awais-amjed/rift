import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../theme/app_text.dart';

/// Start/stop button for the mic test, with the running indicator and whatever
/// went wrong if the microphone could not be opened.
class MicTestControls extends StatelessWidget {
  /// Whether the test is currently running.
  final bool testing;

  /// Whether a start or stop is in flight, which disables the button.
  final bool busy;

  /// Why the microphone could not be opened, if it could not be.
  final String? error;

  final VoidCallback onToggle;

  final ThemeState themeState;

  const MicTestControls({
    super.key,
    required this.testing,
    required this.busy,
    required this.error,
    required this.onToggle,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppButton(
              label: testing ? 'Stop Test' : 'Test Mic',
              onPressed: busy ? null : onToggle,
              variant: testing
                  ? AppButtonVariant.secondary
                  : AppButtonVariant.primary,
              isLoading: busy,
            ),
            const SizedBox(width: 10),
            if (testing)
              Text(
                'Listening…',
                style: AppText.secondary.copyWith(
                  color: themeState.textTertiary,
                ),
              ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          MessageBanner(message: error, kind: MessageBannerKind.error),
        ],
      ],
    );
  }
}
