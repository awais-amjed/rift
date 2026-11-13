import 'package:material_ui/material_ui.dart';

import '../../../../../../../data/classes/channel_override.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../common/selectable_surface.dart';
import '../../../../../../theme/theme_context.dart';

/// Deny, inherit or allow one permission for one role in one channel.
///
/// Three small squares on the app's selection language, in that order — the
/// middle one is "whatever the server says", which is where every bit starts.
class OverrideSwitch extends StatelessWidget {
  final OverrideState value;

  /// Null while saving, or for a bit the viewer does not hold themselves
  /// (`set_channel_override` refuses those).
  final ValueChanged<OverrideState>? onChanged;

  const OverrideSwitch({super.key, required this.value, this.onChanged});

  static const double _size = 30;

  static IconData _icon(OverrideState state) => switch (state) {
    OverrideState.deny => Icons.close_rounded,
    OverrideState.inherit => Icons.horizontal_rule_rounded,
    OverrideState.allow => Icons.check_rounded,
  };

  static String _label(OverrideState state) => switch (state) {
    OverrideState.deny => 'Deny',
    OverrideState.inherit => 'Same as the server',
    OverrideState.allow => 'Allow',
  };

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          for (final state in OverrideState.values)
            Tooltip(
              message: _label(state),
              child: SizedBox.square(
                dimension: _size,
                child: SelectableSurface(
                  selected: state == value,
                  onTap: onChanged == null ? null : () => onChanged!(state),
                  borderRadius: BorderRadius.circular(K.radiusRow),
                  padding: EdgeInsets.zero,
                  child: Center(
                    child: Icon(
                      _icon(state),
                      size: K.iconRow,
                      color: state == value
                          ? themeState.textPrimary
                          : themeState.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
