import 'package:flutter/material.dart';

import '../../../../../common/app_text_field.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../settings/widgets/section_title.dart';

/// Where this server's voice lives: the default region's address, and the one
/// credential pair every region signs with.
///
/// Split out of the old connection section when voice got a page of its own.
/// The server's *name* stayed on Overview — it is what the server is called,
/// not part of how a call is placed — and these three came here, above the
/// region list, because that list is the same fields repeated: the URL below
/// is a second box to hold calls on, and it uses the key and secret typed
/// here.
///
/// The API key and secret are write-only — never fetched to the client — so
/// their fields start blank and are only sent when filled.
class ServerLiveKitSection extends StatelessWidget {
  final TextEditingController livekitUrlCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController secretCtrl;
  final bool enabled;

  const ServerLiveKitSection({
    super.key,
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
        const SectionTitle(label: 'LiveKit'),
        const SizedBox(height: 6),
        Text(
          'The LiveKit this server holds calls on, and the credentials it '
          'signs call tokens with. This address is the first region below.',
          style: AppText.secondary.copyWith(color: themeState.textQuaternary),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: livekitUrlCtrl,
          label: 'LiveKit URL',
          hint: 'wss://livekit.example.com',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
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
          'The API key and secret are stored only on the server and never '
          'sent back — leave them blank to keep the current values.',
          style: AppText.label.copyWith(color: themeState.textTertiary),
        ),
      ],
    );
  }
}
