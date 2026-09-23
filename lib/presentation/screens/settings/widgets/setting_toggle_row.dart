import 'package:flutter/material.dart';

import '../../../common/app_switch.dart';
import '../../../common/setting_row.dart';

/// A [SettingRow] whose control is a switch — the standard layout for a
/// boolean setting.
///
/// A null [onChanged] disables the switch, which is how a platform-specific
/// setting stays visible (with a description explaining why) on platforms
/// that cannot offer it.
class SettingToggleRow extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingToggleRow({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      description: description,
      // Dimmed rather than hidden — a setting this platform can't offer
      // still shows its state, with the description saying why.
      control: Opacity(
        opacity: onChanged == null ? 0.5 : 1,
        child: AppSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}
