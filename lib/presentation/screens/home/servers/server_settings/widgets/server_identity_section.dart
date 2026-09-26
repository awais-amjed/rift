import 'package:flutter/material.dart';

import '../../../../../common/app_text_field.dart';
import '../../../../settings/widgets/section_title.dart';

/// What the server is called.
///
/// One field, and that is the point: this used to carry the LiveKit URL, API
/// key and secret as well, which made the first thing on Overview a form about
/// voice infrastructure. Those moved to the Regions page — see
/// `ServerLiveKitSection` — leaving Overview to say what the server is and who
/// can find it.
class ServerIdentitySection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final bool enabled;

  const ServerIdentitySection({
    super.key,
    required this.nameCtrl,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Server'),
        const SizedBox(height: 14),
        AppTextField(
          controller: nameCtrl,
          label: 'Server name',
          hint: 'My server',
          enabled: enabled,
        ),
      ],
    );
  }
}
