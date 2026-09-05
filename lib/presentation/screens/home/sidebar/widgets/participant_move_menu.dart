import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/voice_move.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// The submenu behind "Move to" — one row per voice channel they could go to.
///
/// The channel they're already in is left out ([VoiceMove.destinations]), so
/// every row does something. Picking one dismisses the whole menu: unlike a
/// role tick, a move happens once and the rows it was showing are stale the
/// moment it lands.
class ParticipantMoveMenu extends StatefulWidget {
  final String userId;

  /// The voice channel they're in now, so it isn't offered as a destination.
  final String? fromChannelId;

  const ParticipantMoveMenu({
    super.key,
    required this.userId,
    required this.fromChannelId,
  });

  @override
  State<ParticipantMoveMenu> createState() => _ParticipantMoveMenuState();
}

class _ParticipantMoveMenuState extends State<ParticipantMoveMenu> {
  /// Which channel is mid-flight, so a second click can't send them twice.
  String? _pending;
  String? _error;

  Future<void> _move(Channel channel) async {
    if (_pending != null) return;
    setState(() {
      _pending = channel.id;
      _error = null;
    });

    final serverCubit = context.read<ServerCubit>();
    final dismiss = ContextMenuScope.of(context);

    final response = await serverCubit.moveUser(
      userId: widget.userId,
      channelId: channel.id,
    );

    if (!mounted) return;
    if (response.success) {
      dismiss?.call();
      return;
    }
    setState(() {
      _pending = null;
      _error = response.error ?? 'Could not move them';
    });
  }

  @override
  Widget build(BuildContext context) {
    final channels = context
        .watch<ServerCubit>()
        .state
        .selectedServer
        ?.channels;
    final destinations = VoiceMove.destinations(
      channels ?? const [],
      from: widget.fromChannelId,
    );

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return ContextMenuPanel(
          heading: 'Move to',
          children: [
            if (destinations.isEmpty)
              _note('No other voice channel to move them to.', themeState),
            for (final channel in destinations)
              ContextMenuItem(
                icon: Icons.volume_up_rounded,
                label: channel.name,
                onTap: () => _move(channel),
                trailing: _pending == channel.id
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const SizedBox(width: 16, height: 16),
              ),
            if (_error != null)
              _note(_error!, themeState, color: CustomColors.error),
          ],
        );
      },
    );
  }

  Widget _note(String text, ThemeState themeState, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Text(
        text,
        style: AppText.label.copyWith(
          fontWeight: FontWeight.w400,
          color: color ?? themeState.textTertiary,
        ),
      ),
    );
  }
}
