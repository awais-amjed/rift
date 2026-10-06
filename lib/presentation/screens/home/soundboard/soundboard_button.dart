import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/popover_surface.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/theme_context.dart';
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
  /// Drawn for the user dock's call row (see [ControlButton.dense]), last in
  /// it. It then takes its own share of the row, so it must sit straight in
  /// the dock's [Row].
  final bool dense;

  const SoundboardButton({super.key, this.dense = false});

  @override
  State<SoundboardButton> createState() => _SoundboardButtonState();
}

class _SoundboardButtonState extends State<SoundboardButton> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  void _toggle() {
    if (_entry != null) {
      _dismiss();
      return;
    }
    // A hand-rolled overlay pinned to a control at the bottom of a phone is
    // a card under the thumb that opened it. The overlay stays for pointer
    // platforms, where it is the right object and the anchoring is done.
    if (context.layoutMode.isCompact) {
      _showSheet();
      return;
    }
    _show();
  }

  /// The cubits the picker needs, captured while this widget's context is
  /// still the live one — an overlay is a sibling of the route and a sheet
  /// is a route of its own, so neither sees any of these from here.
  List<BlocProvider> _providers() => [
    BlocProvider.value(value: context.read<SoundboardCubit>()),
    BlocProvider.value(value: context.read<ThemeCubit>()),
    BlocProvider.value(value: context.read<AppCubit>()),
    // Read live by the picker now, so a role granted mid-call reaches it.
    BlocProvider.value(value: context.read<ServerCubit>()),
  ];

  Future<void> _showSheet() {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: context.theme.bgElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(PopoverSurface.radius),
        ),
      ),
      builder: (_) => MultiBlocProvider(
        providers: _providers(),
        // The sheet does not close on a press, for the same reason the card
        // does not: two in a row is the normal case.
        child: const SoundboardPopover(compact: true),
      ),
    );
  }

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

    final providers = _providers();

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
              providers: providers,
              // Clamped at the top as well as the left. Without a ceiling a
              // full list — the clips plus the divider and the listener
              // controls — ran off the top of a short window and took the
              // header with it; with one, a short window shortens the list.
              child: SoundboardPopover(maxHeight: origin.dy - 16),
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
        final button = ControlButton(
          key: _buttonKey,
          icon: Icons.campaign_rounded,
          isActive: _entry != null,
          tooltip: 'Soundboard',
          onTap: _toggle,
          dense: widget.dense,
        );
        // The gap to the next control is carried here rather than by the
        // row, because this is the one control in it that can be absent —
        // left outside, it would be a hole beside nothing.
        if (widget.dense) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: K.dockCallButtonGap),
              child: button,
            ),
          );
        }
        return Padding(padding: const EdgeInsets.only(right: 4), child: button);
      },
    );
  }
}
