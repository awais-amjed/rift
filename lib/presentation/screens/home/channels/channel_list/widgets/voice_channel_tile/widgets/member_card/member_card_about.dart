import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../../../data/classes/role.dart';
import '../../../../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../../../../logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import '../../../../../../../../../logic/services/time_out_label.dart';
import '../../../../../../../../../logic/services/voice_status_icons.dart';
import '../../../../../../../../common/label_pill.dart';
import '../../../../../../../../theme/app_text.dart';
import '../../../../../../../../theme/custom_colors.dart';
import '../../../../../../../../theme/theme_context.dart';
import '../../../../../../sidebar/widgets/voice_status_row_icons.dart';

/// Who somebody is here and how they are in the call: their roles, a
/// time-out if they have one, and their microphone and headphones in words.
///
/// The words only for a call this device is in: anywhere else their state
/// has not reached us, and a guess would be worse than nothing.
class MemberCardAbout extends StatelessWidget {
  final String userId;
  final String channelId;

  const MemberCardAbout({
    super.key,
    required this.userId,
    required this.channelId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final roles = context.select<ServerMembersCubit, List<Role>>(
      (cubit) => cubit.state.memberRoles[userId] ?? const [],
    );
    final until = context.select<ServerMembersCubit, DateTime?>(
      (cubit) => cubit.state.byId[userId]?.timedOutUntil,
    );
    final timedOut = until != null && until.isAfter(DateTime.now());
    final states = _states(context);

    final lines = <Widget>[
      if (roles.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final role in roles)
              LabelPill(label: role.name, color: role.displayColor),
          ],
        ),
      if (timedOut)
        _line(
          Icons.timer_outlined,
          'Timed out until ${timeOutEndLabel(until)}',
          CustomColors.error,
          theme,
        ),
      if (states != null)
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (states.isEmpty)
              _line(Icons.mic_rounded, 'Mic on', theme.textTertiary, theme)
            else
              for (final state in states)
                _line(
                  VoiceStatusRowIcons.iconOf(state),
                  _words(state),
                  VoiceStatusRowIcons.colorOf(state, theme),
                  theme,
                ),
          ],
        ),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: lines,
    );
  }

  /// Their state in the call, or null when this device is not in it with
  /// them. Selected as names, so a breath — which changes the roster but not
  /// this — redraws nothing.
  List<VoiceStatusIcon>? _states(BuildContext context) {
    final cannotHear =
        context.select<ServerMembersCubit, bool>(
          (cubit) => cubit.state.byId[userId]?.isBot ?? false,
        ) &&
        !context.watch<VoiceListenersCubit>().hears(channelId, userId);
    final key = context.select<AppCubit, String?>((cubit) {
      final live = cubit.state.participants
          .where((p) => p.userId == userId && !p.isShare)
          .firstOrNull;
      if (live == null) return null;
      return voiceStatusIcons(
        live,
        mutedForYou: false,
        cannotHear: cannotHear,
      ).map((icon) => icon.name).join(',');
    });
    if (key == null) return null;
    final icons = [
      for (final name in key.split(','))
        if (name.isNotEmpty) VoiceStatusIcon.values.byName(name),
    ];
    final deafened =
        icons.contains(VoiceStatusIcon.deafened) ||
        icons.contains(VoiceStatusIcon.deafenedByModerator);
    return [
      for (final icon in icons)
        // Sharing has its own lines, and deafened already says the
        // microphone is off.
        if (icon != VoiceStatusIcon.sharingScreen &&
            icon != VoiceStatusIcon.sharingSound &&
            !(deafened && icon == VoiceStatusIcon.muted))
          icon,
    ];
  }

  static String _words(VoiceStatusIcon icon) => switch (icon) {
    VoiceStatusIcon.deafened => 'Deafened',
    VoiceStatusIcon.deafenedByModerator => 'Deafened by a moderator',
    VoiceStatusIcon.cannotHear => 'Can’t hear the call',
    VoiceStatusIcon.muted => 'Muted',
    VoiceStatusIcon.mutedByModerator => 'Muted by a moderator',
    VoiceStatusIcon.waitingToTalk => 'Push to talk',
    VoiceStatusIcon.mutedForYou => 'Muted for you',
    VoiceStatusIcon.sharingScreen => 'Sharing their screen',
    VoiceStatusIcon.sharingSound => 'Sharing sound',
  };

  static Widget _line(
    IconData icon,
    String text,
    Color color,
    ThemeState theme,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 5,
    children: [
      Icon(icon, size: 14, color: color),
      Flexible(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.secondary.copyWith(color: theme.textSecondary),
        ),
      ),
    ],
  );
}
