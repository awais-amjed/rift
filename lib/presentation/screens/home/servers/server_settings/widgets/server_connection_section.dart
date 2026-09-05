import 'package:flutter/material.dart';

import '../../../../../common/app_text_field.dart';
import '../../../../../theme/app_text.dart';
import '../../../../settings/widgets/section_title.dart';
import '../../../../../theme/theme_context.dart';

/// The identity + LiveKit half of the server settings dialog.
///
/// The API key and secret are write-only — never fetched to the client — so
/// their fields start blank and are only sent when filled.
class ServerConnectionSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController livekitUrlCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController secretCtrl;
  final bool enabled;

  const ServerConnectionSection({
    super.key,
    required this.nameCtrl,
    required this.livekitUrlCtrl,
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
        SectionTitle(label: 'Server'),
        const SizedBox(height: 14),
        AppTextField(
          controller: nameCtrl,
          label: 'Server Name',
          hint: 'My Server',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: livekitUrlCtrl,
          label: 'LiveKit URL',
          hint: 'wss://livekit.example.com',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: apiKeyCtrl,
          label: 'LiveKit API Key',
          hint: 'Leave blank to keep current',
          enabled: enabled,
          obscureText: true,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: secretCtrl,
          label: 'LiveKit Secret Key',
          hint: 'Leave blank to keep current',
          enabled: enabled,
          obscureText: true,
        ),
        const SizedBox(height: 8),
        Text(
          'The API key and secret are stored only on the server and never '
          'sent back — leave them blank to keep the current values.',
          style: AppText.label.copyWith(color: themeState.textTertiary),
        ),
      ],
    );
  }
}
