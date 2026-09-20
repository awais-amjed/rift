import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../controls/widgets/control_button.dart';
import 'soundboard_popover.dart';

/// The soundboard's place in the call's control bar.
///
/// Shown to everyone in a call, including somebody who may not press one:
/// the clips are the server's and are worth seeing, and the volume control
/// at the foot of the popover is the listener's business whatever their
/// permissions are. It is only hidden when the server has no soundboard at
/// all and this member could not add one — a button onto an empty list with
/// no way to fill it.
class SoundboardButton extends StatefulWidget {
  const SoundboardButton({super.key});

  @override
  State<SoundboardButton> createState() => _SoundboardButtonState();
}

class _SoundboardButtonState extends State<SoundboardButton> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  void _toggle() => _entry != null ? _dismiss() : _show();

  void _show() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.of(context).size;
    // Clamped to the window rather than anchored blindly: the bar is centred,
    // so on a narrow window this button is close enough to the edge for a
    // 260px card to hang off it.
    final left = (origin.dx + SoundboardPopover.width > screen.width)
        ? screen.width - SoundboardPopover.width - 8
        : origin.dx;

    // Captured before entering the overlay, which is a sibling of the route
    // and so sees none of its providers.
    final soundboardCubit = context.read<SoundboardCubit>();
    final themeCubit = context.read<ThemeCubit>();
    final appCubit = context.read<AppCubit>();
    final canPlay = soundboardCubit.canPlay;

    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismiss,
            ),
          ),
          Positioned(
            left: left,
            bottom: screen.height - origin.dy + 8,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: soundboardCubit),
                BlocProvider.value(value: themeCubit),
                BlocProvider.value(value: appCubit),
              ],
              child: SoundboardPopover(canPlay: canPlay),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SoundboardCubit, SoundboardState>(
      buildWhen: (before, after) =>
          before.isEmpty != after.isEmpty || before.status != after.status,
      builder: (context, state) {
        if (state.isEmpty && !context.read<SoundboardCubit>().canManage) {
          return const SizedBox.shrink();
        }
        // The gap to the next control is carried here rather than by the
        // bar, because this is the one control in the row that can be absent
        // — left outside, it would be a 4px hole in the pill.
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: ControlButton(
            key: _buttonKey,
            icon: Icons.graphic_eq_rounded,
            isActive: _entry != null,
            tooltip: 'Soundboard',
            onTap: _toggle,
          ),
        );
      },
    );
  }
}
