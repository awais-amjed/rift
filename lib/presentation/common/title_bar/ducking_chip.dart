import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../data/constants.dart';
import '../../../data/enums/ducking_preference.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/ducking/ducking_cubit.dart';
import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../routing/app_routes.dart';
import '../../screens/settings/widgets/settings_tab.dart';
import '../../theme/custom_colors.dart';
import '../status_chip.dart';

/// "Did your other apps go quiet?" beside the window controls, for a while
/// after Windows turns the person's other apps down during a Rift call
/// ([DuckingCubit.hintFor]); pressing it shows how to stop it.
///
/// Windows' "ducking" is the first thing people ask about after their first
/// call on Windows: the music went quiet and nothing in Rift said why. This
/// was a toast, which was too loud for a hint — and Windows reports a duck
/// even when the person hears none (an app may ignore it, or play on another
/// device), so a toast also interrupted people for nothing. A chip says it
/// where it can be found, and goes by itself.
///
/// Rift's own call is the usual cause ([DuckingState.lastByRift]). One while
/// Rift is in a call for another reason counts too: the music still went
/// quiet during a Rift call, and the fix is the same.
class DuckingChip extends StatelessWidget {
  const DuckingChip({super.key});

  @override
  Widget build(BuildContext context) {
    final preference = context.select<DuckingCubit, DuckingPreference?>(
      (c) => c.state.hinting ? c.state.preference : null,
    );
    final byRift = context.select<DuckingCubit, bool>(
      (c) => c.state.lastByRift,
    );
    final inCall = context.select<LiveKitCubit, bool>((c) => c.state.inCall);
    final wanted = context.select<AppCubit, bool>(
      (c) => c.state.showDuckingHint,
    );
    if (preference == null || !wanted || !(byRift || inCall)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: K.titleBarChipMaxWidth),
        child: StatusChip(
          icon: Icons.volume_down_rounded,
          // A question in the person's words, not Windows': "ducking" means
          // nothing to most people, and the duck is not always heard.
          label: 'Did your other apps go quiet?',
          color: CustomColors.warning,
          tooltip:
              'During calls, Windows ${preference.effect}. Click to see how '
              'to stop it.',
          onTap: () {
            context.read<DuckingCubit>().dismissHint();
            _openFix();
          },
        ),
      ),
    );
  }

  /// Settings, at the section that walks through the change. The bar sits
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
