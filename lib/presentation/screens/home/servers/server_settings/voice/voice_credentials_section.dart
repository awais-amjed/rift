import 'package:flutter/material.dart';

import '../../../../../common/app_text_field.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../settings/widgets/section_title.dart';

/// The API key and secret the *first* region signs call tokens with.
///
/// Only that one: every region added afterwards carries its own pair, typed
/// when it is added, because a key shared across boxes means a break-in on
/// the cheapest of them mints tokens for calls on all of them. This pair is
/// the server's own LiveKit's, which is what the first region is.
///
/// Under the region list rather than over it, which is where the LiveKit
/// fields started. A reader opening Voice wants to see where calls are held;
/// the credential is a detail about one of them.
///
/// The key and secret are write-only — never fetched to the client — so their
/// fields start blank and are only sent when filled. That is also why this is
/// the only part of the page with a Save: there is nothing here to act on
/// immediately, only two secrets that are typed together and sent together.
class VoiceCredentialsSection extends StatelessWidget {
  final TextEditingController apiKeyCtrl;
  final TextEditingController secretCtrl;
  final bool enabled;

  const VoiceCredentialsSection({
    super.key,
    required this.apiKeyCtrl,
    required this.secretCtrl,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Credentials'),
        const SizedBox(height: 6),
        Text(
          'What the first region signs call tokens with — the server\'s own '
          'LiveKit. Every other region has a key of its own, typed when it is '
          'added.',
          style: AppText.secondary.copyWith(color: themeState.textQuaternary),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: apiKeyCtrl,
          label: 'LiveKit API key',
          hint: 'Leave blank to keep current',
          enabled: enabled,
          obscureText: true,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: secretCtrl,
          label: 'LiveKit secret key',
          hint: 'Leave blank to keep current',
          enabled: enabled,
          obscureText: true,
        ),
        const SizedBox(height: 8),
        Text(
          'Stored only on the server and never sent back — leave them blank '
          'to keep the current values.',
          style: AppText.label.copyWith(color: themeState.textTertiary),
        ),
      ],
    );
  }
}
