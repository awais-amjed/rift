import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/central_dm/central_dm_cubit.dart' as central;
import '../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'central_dm_chat_view.dart';
import 'server_dm_chat_view.dart';
import 'widgets/dm_side_panel.dart';

/// The Home (Direct Messages) surface: conversation panel on the left, the
/// open conversation on the right. Two tiers live side by side — central DMs
/// (discovery funnel, quota-limited) and DMs on the selected server
/// (unlimited) — with only one conversation open at a time.
class HomeDmView extends StatelessWidget {
  const HomeDmView({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return Container(
      color: themeState.bgPrimary,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(width: 280, child: DmSidePanel()),
          Container(width: 1, color: themeState.borderPrimary),
          Expanded(child: _buildChatArea(context)),
        ],
      ),
    );
  }

  Widget _buildChatArea(BuildContext context) {
    final serverOpen = context.watch<DmCubit>().state.openPeerId != null;
    final centralOpen =
        context.watch<central.CentralDmCubit>().state.openPeerId != null;

    if (centralOpen) return const CentralDmChatView();
    if (serverOpen) return const ServerDmChatView();
    return const _EmptyChatHint();
  }
}

class _EmptyChatHint extends StatelessWidget {
  const _EmptyChatHint();

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 44,
            color: themeState.textQuaternary,
          ),
          const SizedBox(height: 12),
          Text(
            'Pick a conversation',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: themeState.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'All messages are end-to-end encrypted.',
            style: TextStyle(fontSize: 13, color: themeState.textTertiary),
          ),
        ],
      ),
    );
  }
}
