import 'package:material_ui/material_ui.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../common/app_dropdown.dart';
import '../../../../../common/setting_row.dart';

/// How far back a clip goes: one of [AppCubit.clipLengths].
class ClipLengthChoice extends StatelessWidget {
  final int seconds;
  final ValueChanged<int> onChanged;

  const ClipLengthChoice({
    super.key,
    required this.seconds,
    required this.onChanged,
  });

  /// Also the trim view's, so a length reads the same in both.
  static String labelOf(int seconds) => switch (seconds) {
    60 => '1 minute',
    120 => '2 minutes',
    _ => '$seconds seconds',
  };

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: 'Clip length',
      description: 'How far back a clip goes.',
      control: SizedBox(
        width: 150,
        child: AppDropdown<int>(
          value: seconds,
          options: [
            for (final length in AppCubit.clipLengths)
              AppDropdownOption(value: length, label: labelOf(length)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
