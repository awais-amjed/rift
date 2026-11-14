import 'package:material_ui/material_ui.dart';

import '../../../../../../../data/classes/channel_override.dart';
import '../../../../../../common/segmented_control.dart';

/// Block, leave alone or allow one permission for one role in one channel.
///
/// Words, not ✕ – ✓: the middle one was a dash with "Same as the server"
/// behind a tooltip, and even the owner had to stop and work out what it
/// meant. "Default" is said in full beside it (`OverrideRow`), so the word
/// only has to name the choice.
class OverrideSwitch extends StatelessWidget {
  final OverrideState value;

  /// Null while saving, or for a bit the viewer does not hold themselves
  /// (`set_channel_override` refuses those).
  final ValueChanged<OverrideState>? onChanged;

  const OverrideSwitch({super.key, required this.value, this.onChanged});

  /// Wide enough for the three words side by side.
  static const double width = 240;

  static const _options = [
    SegmentOption(value: OverrideState.deny, label: 'Block'),
    SegmentOption(value: OverrideState.inherit, label: 'Default'),
    SegmentOption(value: OverrideState.allow, label: 'Allow'),
  ];

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onChanged == null ? 0.5 : 1,
      child: SegmentedControl<OverrideState>(
        options: _options,
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
