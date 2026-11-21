import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/services/call_clip/clip_library.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../home/call_clip/stored_clip_opener.dart';
import '../../../../home/call_clip/widgets/clip_history_list.dart';
import '../../section_title.dart';
import '../../setting_toggle_row.dart';
import 'widgets/clip_length_choice.dart';

/// Clipping a call (CALLS.md, "Clipping a call"): keeping the last stretch
/// of what the call played, so the clip shortcut can save it or put it on the
/// soundboard. Windows and Linux only ([HostPlatform.clipsCalls]).
///
/// The call is told: the hint says so before it is turned on, since that is
/// when it matters.
class ClippingSection extends StatelessWidget {
  final AppState appState;

  const ClippingSection({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppCubit>();
    final on = appState.clippingEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Clipping'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Keep the call for clips',
          description:
              'Save what was just said with the clip shortcut, set in '
              'Keybinds.',
          value: on,
          onChanged: app.setClippingEnabled,
        ),
        const SizedBox(height: 8),
        Text(
          'People in the call see that you have clipping on.',
          style: AppText.secondary.copyWith(color: context.theme.textTertiary),
        ),
        if (on) ...[
          const SizedBox(height: 14),
          ClipLengthChoice(
            seconds: appState.clipSeconds,
            onChanged: app.setClipSeconds,
          ),
          const SizedBox(height: 14),
          SettingToggleRow(
            title: 'Include my mic',
            description: 'Your own voice in clips, as the call hears it.',
            value: appState.clipIncludeMic,
            onChanged: app.setClipIncludeMic,
          ),
        ],
        // Shown with clipping off too: what was kept before stays until it
        // is deleted, and this is where it can be, outside a call.
        const SizedBox(height: 20),
        Text(
          'Recent clips',
          style: AppText.strong.copyWith(color: context.theme.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'The last ${ClipLibrary.keep}, kept on this device, sealed with '
          'your account. Open one to trim it again.',
          style: AppText.secondary.copyWith(color: context.theme.textTertiary),
        ),
        const SizedBox(height: 8),
        ClipHistoryList(onOpen: (clip) => openStoredClip(context, clip)),
      ],
    );
  }
}
