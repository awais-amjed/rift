import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../routing/app_routes.dart';
import '../add_server/add_server_dialog.dart';
import 'widgets/rail_chip_button.dart';
import 'widgets/rail_server_chip.dart';

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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
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
      },
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

  Widget _buildServerList(BuildContext context) {
    // AppState churns on every mic/camera toggle, so the rail listens for the
    // one field it cares about rather than watching the whole cubit.
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) => a.surface != b.surface,
      builder: (context, appState) {
        return BlocBuilder<ServerCubit, ServerState>(
          buildWhen: (a, b) =>
              a.servers != b.servers ||
              a.selectedServerId != b.selectedServerId,
          builder: (context, serverState) {
            return BlocBuilder<ServerNotificationsCubit, NotificationsState>(
              builder: (context, notifications) {
                return SingleChildScrollView(
                  child: Column(
                    spacing: 8,
                    children: [
                      for (final server in serverState.servers)
                        RailServerChip(
                          server: server,
                          // Opening Home doesn't leave the server, but it does
                          // mean the rail's selection is Home — two things
                          // can't both be current.
                          isSelected:
                              server.id == serverState.selectedServerId &&
                              appState.surface != HomeSurface.centralDms,
                          unreadCount: notifications.unreadForServer(server.id),
                          onTap: () {
                            context.read<AppCubit>().setSurface(
                              HomeSurface.server,
                            );
                            context.read<ServerCubit>().selectServer(server);
                          },
                        ),
                      RailChipButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Add a server',
                        ghostRing: true,
                        onTap: () => _openAddServerDialog(context),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _openAddServerDialog(BuildContext context) {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<AppCubit>()),
        ],
        child: const AddServerDialog(),
      ),
    );
  }
}
