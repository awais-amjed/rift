import 'package:material_ui/material_ui.dart';

import '../../../../../../../data/classes/channel_override.dart';
import '../../../../../../../data/enums/channel_type.dart';
import '../../../../../../../data/enums/server_permission.dart';
import '../../../../../../common/setting_row.dart';
import 'override_switch.dart';

/// Every permission a channel of [type] can override, for one role's row.
class OverrideList extends StatelessWidget {
  final ChannelType type;
  final ChannelOverride row;

  /// What the viewer holds on the server: a bit they lack is shown and not
  /// offered, as in the roles editor.
  final int viewerBits;

  /// Null while saving.
  final ValueChanged<ChannelOverride>? onChanged;

  const OverrideList({
    super.key,
    required this.type,
    required this.row,
    required this.viewerBits,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 14,
      children: [
        for (final permission in ChannelOverride.overridableIn(type))
          SettingRow(
            title: permission.label,
            description: permission.description,
            control: OverrideSwitch(
              value: row.stateOf(permission),
              onChanged: onChanged == null || !viewerBits.has(permission)
                  ? null
                  : (state) => onChanged!(row.withState(permission, state)),
            ),
          ),
      ],
    );
  }
}
