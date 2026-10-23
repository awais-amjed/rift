import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_sheet.dart';
import '../../../common/call_server_scope.dart';
import '../../../common/server_scope.dart';
import '../../../common/show_custom_dialog.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import '../controls/widgets/control_button.dart';
import 'soundboard_popover.dart';

/// Over the widget budget and one job: the soundboard's button in the control
/// bar and the popover it opens.
///
/// The soundboard's place in the call's control bar.
///
/// Shown to everyone in a call, including somebody who may not press one:
/// the clips are the server's and are worth seeing, and the volume control
/// at the foot of the popover is the listener's business whatever their
/// permissions are. It is only hidden when the server has no soundboard at
/// all and this member could not add one — a button onto an empty list with
/// no way to fill it.
///
/// The call's server's soundboard ([CallServerScope]), whichever server is
/// being read: a press is played from the call's library by everyone in it.
class SoundboardButton extends StatelessWidget {
  /// Drawn for the user dock's call row (see [ControlButton.dense]), last in
  /// it. It then takes its own share of the row, so it must sit straight in
  /// the dock's [Row].
  final bool dense;

  const SoundboardButton({super.key, this.dense = false});

  @override
  Widget build(BuildContext context) =>
      CallServerScope(child: _CallSoundboardButton(dense: dense));
}

class _CallSoundboardButton extends StatefulWidget {
  final bool dense;

  const _CallSoundboardButton({required this.dense});

  @override
  State<_CallSoundboardButton> createState() => _CallSoundboardButtonState();
}

class _CallSoundboardButtonState extends State<_CallSoundboardButton> {
  final _buttonKey = GlobalKey();

  /// The card while it is open, and the navigator it is on, so a call that
  /// ends under it takes it away.
  ///
  /// A route rather than an entry put straight on the overlay. A route pushed
  /// later goes above the last route, not above everything, so a dialog
  /// opened while the card was up — Leave server from the rail — drew under
  /// it, and the card heard neither Escape nor a right-click outside.
  Route<void>? _route;
  NavigatorState? _navigator;

  void _toggle() {
    if (_route != null) {
      setState(_dismiss);
      return;
    }
    // A card pinned to a control at the bottom of a phone is a card under
    // the thumb that opened it. The card stays for pointer platforms, where
    // it is the right object and the anchoring is done.
    if (context.layoutMode.isCompact) {
      _showSheet();
      return;
    }
    _show();
  }

  /// The cubits the picker needs, captured while this widget's context is
  /// still the live one — an overlay is a sibling of the route and a sheet
  /// is a route of its own, so neither sees any of these from here.
  ///
  /// Each typed by hand: in a `List<BlocProvider>` the list's type is what
  /// `BlocProvider.value` infers from, so every one of these was provided as
  /// the base type and found by nothing. The picker read the soundboard above
  /// the overlay instead — the selected server's, an empty library mid-call
  /// on another server (`test/provider_types_test.dart`).
  List<BlocProvider> _providers() => [
    BlocProvider<SoundboardCubit>.value(value: context.read<SoundboardCubit>()),
    BlocProvider<ThemeCubit>.value(value: context.read<ThemeCubit>()),
    BlocProvider<AppCubit>.value(value: context.read<AppCubit>()),
    // Read live by the picker now, so a role granted mid-call reaches it.
    BlocProvider<ServerCubit>.value(value: context.read<ServerCubit>()),
  ];

  Future<void> _showSheet() {
    return showAppSheet<void>(
      context,
      MultiBlocProvider(
        providers: _providers(),
        // The sheet does not close on a press, for the same reason the card
        // does not: two in a row is the normal case.
        child: const SoundboardPopover(compact: true),
      ),
    );
  }

  Future<void> _show() async {
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

    // A press outside closes it and goes no further, as every other menu's
    // does; a press inside leaves it open, since two in a row is the normal
    // case.
    final route = RawDialogRoute<void>(
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.transparent,
      transitionDuration: AppMotion.react,
      pageBuilder: (routeContext, _, _) => FocusScope(
        autofocus: true,
        onKeyEvent: (_, event) => closeOnEscape(routeContext, event),
        child: Stack(
          children: [
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
      ),
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    final navigator = Navigator.of(context, rootNavigator: true);
    setState(() {
      _route = route;
      _navigator = navigator;
    });
    await navigator.push(route);
    if (mounted && _route == route) setState(() => _route = null);
  }

  void _dismiss() {
    final route = _route;
    _route = null;
    if (route != null && route.isActive) _navigator?.removeRoute(route);
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // From the server's state, not a getter on the soundboard cubit: a role
    // granted with the library still empty has to bring the button in, and
    // only a change to this state rebuilds the button when it happens.
    final serverId = ServerScope.of(context).serverId;
    final canManage = context.select<ServerCubit, bool>(
      (cubit) =>
          cubit.state
              .permissionsOn(serverId)
              ?.can(ServerPermission.manageSoundboard) ??
          false,
    );
    return BlocBuilder<SoundboardCubit, SoundboardState>(
      buildWhen: (before, after) =>
          before.isEmpty != after.isEmpty || before.status != after.status,
      builder: (context, state) {
        if (state.isEmpty && !canManage) return const SizedBox.shrink();
        final button = ControlButton(
          key: _buttonKey,
          icon: Icons.campaign_rounded,
          isActive: _route != null,
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
