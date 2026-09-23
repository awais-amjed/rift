import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../routing/app_routes.dart';
import '../../../../theme/theme_context.dart';
import '../add_server/add_server_dialog.dart';
import 'widgets/rail_chip_button.dart';
import 'widgets/rail_server_list.dart';

/// The permanent vertical rail down the left edge of the sidebar panel.
///
/// It separates the app's two tiers: Home at the top is the central account —
/// your DMs, independent of any server — and everything below it is one
/// self-hosted server each. That separation is the reason the rail exists;
/// the old switcher popover hid the server list behind a click and left no
/// room to say which tier you were in.
class ServerRail extends StatelessWidget {
  /// Extra room at the top when the title bar is hidden.
  final double topPadding;

  const ServerRail({super.key, this.topPadding = 0});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      width: K.serverRailWidth,
      decoration: BoxDecoration(
        color: themeState.railStrip,
        border: Border(right: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Column(
        children: [
          SizedBox(height: topPadding + 12),
          _buildHomeButton(context),
          _buildDivider(themeState),
          Expanded(child: _buildServerList(context)),
          const SizedBox(height: 8),
          RailChipButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildHomeButton(BuildContext context) {
    final unread = context.select<CentralDmCubit, int>(
      (c) => c.state.homeBadge,
    );
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) => a.surface != b.surface,
      builder: (context, appState) {
        return RailChipButton(
          icon: Icons.forum_rounded,
          tooltip: unread > 0
              ? 'Home — $unread unread central DM${unread == 1 ? '' : 's'}'
              : 'Home — your central DMs',
          isSelected: appState.surface == HomeSurface.centralDms,
          unreadCount: unread,
          onTap: () =>
              context.read<AppCubit>().setSurface(HomeSurface.centralDms),
        );
      },
    );
  }

  Widget _buildDivider(ThemeState themeState) {
    return Container(
      width: 26,
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: themeState.borderElevated,
    );
  }

  /// The servers, then the way to add one.
  ///
  /// The add chip is outside the scrolling list on purpose: it is not a
  /// server, it cannot be dragged, and a rail long enough to scroll is
  /// exactly when it must not scroll away.
  Widget _buildServerList(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Flexible(child: RailServerList()),
        RailChipButton(
          icon: Icons.add_rounded,
          tooltip: 'Add a server',
          ghostRing: true,
          onTap: () => _openAddServerDialog(context),
        ),
      ],
    );
  }

  void _openAddServerDialog(BuildContext context) {
    showCustomDialog(
      context: context,
      build: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<AppCubit>()),
        ],
        child: const AddServerDialog(),
      ),
    );
  }
}
