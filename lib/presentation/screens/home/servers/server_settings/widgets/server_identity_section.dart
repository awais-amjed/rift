import 'package:flutter/material.dart';

import '../../../../../common/app_text_field.dart';
import '../../../../settings/widgets/section_title.dart';
import 'server_icon_picker.dart';

/// What the server is called, and its icon.
///
/// Those two and nothing else, and that is the point: this used to carry the LiveKit URL, API
/// key and secret as well, which made the first thing on Overview a form about
/// voice infrastructure. Those moved to the Regions page — see
/// `ServerLiveKitSection` — leaving Overview to say what the server is and who
/// can find it.
class ServerIdentitySection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final ServerIconPicker iconPicker;
  final bool enabled;

  const ServerIdentitySection({
    super.key,
    required this.nameCtrl,
    required this.iconPicker,
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
        iconPicker,
        const SizedBox(height: 16),
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
