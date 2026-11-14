import 'package:material_ui/material_ui.dart';

import '../../../../../../../data/classes/channel_override.dart';
import '../../../../../../../data/classes/role.dart';
import '../../../../../../../data/enums/channel_type.dart';
import '../../../../../../../data/enums/server_permission.dart';
import 'override_row.dart';
import 'override_switch.dart';

/// Every permission a channel of [type] can override, for one role's row.
class OverrideList extends StatelessWidget {
  final ChannelType type;

  /// The role being edited, and its row here.
  final Role role;
  final ChannelOverride row;

  /// The server's `@everyone` role and its row here, as edited so far: what
  /// "Default" comes to for any other role starts from both.
  final Role everyone;
  final ChannelOverride everyoneRow;

  /// What the viewer holds on the server: a bit they lack is shown and not
  /// offered, as in the roles editor.
  final int viewerBits;

  /// Null while saving.
  final ValueChanged<ChannelOverride>? onChanged;

  const OverrideList({
    super.key,
    required this.type,
    required this.role,
    required this.row,
    required this.everyone,
    required this.everyoneRow,
    required this.viewerBits,
    this.onChanged,
  });

  int get _serverBits => role.isEveryone
      ? everyone.permissions
      : everyone.permissions | role.permissions;

  /// `@everyone`'s own row is applied as the role's row, not before it.
  ChannelOverride? get _before => role.isEveryone ? null : everyoneRow;

  /// The first bit up [permission]'s chain (`ChannelOverride.needs`) that
  /// this role doesn't get here, if any.
  ServerPermission? _blockedBy(ServerPermission permission) {
    for (
      var needed = ChannelOverride.needs(permission);
      needed != null;
      needed = ChannelOverride.needs(needed)
    ) {
      if (!ChannelOverride.resultFor(
        needed,
        row: row,
        serverBits: _serverBits,
        everyoneRow: _before,
      )) {
        return needed;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final who = role.isEveryone ? 'everyone' : role.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: 14,
      children: [
        for (final permission in ChannelOverride.overridableIn(type))
          _row(permission, who),
      ],
    );
  }

  Widget _row(ServerPermission permission, String who) {
    // A file, a poll or @all where they can't post — shown blocked, and not
    // offered, while the bit they need is. Nothing is stored for it, so
    // lifting Read-only brings back whatever was chosen.
    final blockedBy = _blockedBy(permission);
    if (blockedBy != null) {
      return OverrideRow(
        permission: permission,
        note:
            'Blocked while $who can\'t ${blockedBy.label.toLowerCase()} here',
        control: const OverrideSwitch(value: OverrideState.deny),
      );
    }
    final byDefault = ChannelOverride.defaultFor(
      permission,
      serverBits: _serverBits,
      everyoneRow: _before,
    );
    return OverrideRow(
      permission: permission,
      note: 'Default for $who: ${byDefault ? 'allowed' : 'not allowed'}',
      control: OverrideSwitch(
        value: row.stateOf(permission),
        onChanged: onChanged == null || !viewerBits.has(permission)
            ? null
            : (state) => onChanged!(row.withState(permission, state)),
      ),
    );
  }
}
