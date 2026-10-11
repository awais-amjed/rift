import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/enums/ducking_preference.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/ducking/ducking_cubit.dart';
import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../logic/helper_methods.dart';
import '../../routing/app_routes.dart';
import '../../screens/settings/widgets/settings_tab.dart';
import '../app_toast.dart';

/// Says so when Windows turns the person's other apps down during a Rift
/// call, and offers to show them how to stop it.
///
/// Windows' "ducking" is the first thing people ask about after their first
/// call on Windows: the music went quiet and nothing in Rift said why. A
/// toast rather than a dialog, so it is never in the way of the call: it
/// leaves after a few seconds unless the pointer is on it. Once per duck —
/// Windows ducks once when a call's sound opens — until the person picks
/// "Don't show again"; Settings can turn it back on.
///
/// Rift's own call is the usual cause, and the duck says so
/// ([DuckingState.lastByRift]). One while Rift is in a call for another
/// reason counts too: the music still went quiet during a Rift call, and the
/// fix is the same.
class DuckingHintListener extends StatelessWidget {
  final Widget child;

  const DuckingHintListener({super.key, required this.child});

  /// Long enough to read two lines and reach a button.
  static const _shown = Duration(seconds: 6);

  @override
  Widget build(BuildContext context) {
    return BlocListener<DuckingCubit, DuckingState>(
      listenWhen: (before, after) => after.ducks > before.ducks,
      listener: (context, state) {
        final app = context.read<AppCubit>();
        if (!app.state.showDuckingHint) return;
        if (!state.lastByRift && !context.read<LiveKitCubit>().state.inCall) {
          return;
        }
        final effect = (state.preference ?? DuckingPreference.lowerBy80).effect;
        HelperMethods.showToast(
          title: 'Your other apps got quieter',
          description:
              'During calls, Windows $effect. You can switch that off.',
          autoCloseDuration: _shown,
          actions: [
            ToastAction(label: 'Fix it', primary: true, onPressed: _openFix),
            ToastAction(
              label: "Don't show again",
              onPressed: () => app.setShowDuckingHint(false),
            ),
          ],
        );
      },
      child: child,
    );
  }

  /// Settings, at the section that walks through the change. The toast sits
  /// above the navigator, so it goes through the router's own context.
  static void _openFix() {
    final router = GoRouter.of(AppRoutes.context);
    const target = SettingsTarget(
      SettingsTab.voiceAndAudio,
      section: SettingsSection.ducking,
    );
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (here == AppRoutes.settings) {
      router.pushReplacement(AppRoutes.settings, extra: target);
    } else {
      router.push(AppRoutes.settings, extra: target);
    }
  }
}
