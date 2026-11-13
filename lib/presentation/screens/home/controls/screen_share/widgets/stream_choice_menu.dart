import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';

/// One option in a [StreamChoiceMenu].
typedef StreamChoice = ({String label, bool chosen, VoidCallback onTap});

/// One of the running share's settings — its resolution, frame rate or
/// codec — as a list of the choices the share dialog offers. A pick applies
/// at once and leaves the menu open, so the tick can be seen to move; the
/// picture blinks for viewers while it is published again.
class StreamChoiceMenu extends StatelessWidget {
  final String heading;

  /// The choices for the share as it is now: the frame rates on offer
  /// depend on the resolution, so they are listed again on every change.
  final List<StreamChoice> Function(ScreenshareState state) choices;

  const StreamChoiceMenu({
    super.key,
    required this.heading,
    required this.choices,
  });

  static const double _width = 200;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScreenshareCubit, ScreenshareState>(
      buildWhen: (prev, curr) =>
          prev.settings != curr.settings || prev.codec != curr.codec,
      builder: (context, state) => ContextMenuPanel(
        heading: heading,
        maxWidth: _width,
        children: [
          for (final choice in choices(state))
            ContextMenuItem(
              label: choice.label,
              trailing: choice.chosen
                  ? const Icon(Icons.check_rounded, size: K.iconRow)
                  : null,
              // Picking the current one again would republish for nothing.
              onTap: choice.chosen ? () {} : choice.onTap,
            ),
        ],
      ),
    );
  }
}
