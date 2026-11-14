import 'package:material_ui/material_ui.dart';

import '../../../../../../../data/enums/server_permission.dart';
import '../../../../../../common/setting_row.dart';
import '../../../../../../theme/app_text.dart';
import '../../../../../../theme/theme_context.dart';
import 'override_switch.dart';

/// One permission for one role: what it is, a line saying what it comes to
/// for that role here, and the switch.
///
/// The line says what "Default" comes to, because it is the one choice
/// whose result depends on something else — the server's roles and, for a
/// role below `@everyone`, this channel's `@everyone` row — or that the bit
/// is blocked by another one (`ChannelOverride.needs`).
class OverrideRow extends StatelessWidget {
  final ServerPermission permission;

  /// "Default for DJs: allowed", or "Blocked while everyone can't send
  /// messages".
  final String note;

  final OverrideSwitch control;

  const OverrideRow({
    super.key,
    required this.permission,
    required this.note,
    required this.control,
  });

  /// Below this, the switch goes under the words rather than beside them —
  /// beside them on a phone, the words got a column a word wide.
  static const double _sideBySide = 520;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _sideBySide) {
          return SettingRow(
            title: permission.label,
            description: '${permission.description}\n$note',
            control: SizedBox(width: OverrideSwitch.width, child: control),
          );
        }
        final theme = context.theme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  permission.label,
                  style: AppText.row.copyWith(color: theme.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  '${permission.description}\n$note',
                  style: AppText.secondary.copyWith(
                    height: 1.4,
                    color: theme.textTertiary,
                  ),
                ),
              ],
            ),
            control,
          ],
        );
      },
    );
  }
}
