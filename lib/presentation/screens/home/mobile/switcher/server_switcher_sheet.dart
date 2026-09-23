import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/home_surface.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/notifications/server_notifications_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_modal_header_button.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/media_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../profile/user_dock/user_dock.dart';
import '../../servers/add_server/add_server_dialog.dart';
import 'switcher_add_row.dart';
import 'switcher_home_row.dart';
import 'switcher_server_list.dart';

/// Opens the switcher: every server, Home, and your own controls, sliding in
/// from the edge the list is anchored to.
///
/// A route rather than a drawer inside the shell, so the system back gesture
/// closes it the way it closes anything else laid over a screen.
Future<void> showServerSwitcherSheet(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close switcher',
    barrierColor: MediaColors.scrim,
    transitionDuration: K.sidebarMotion,
    pageBuilder: (_, _, _) => const ServerSwitcherSheet(),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: AppMotion.panel)),
      child: child,
    ),
  );
}

/// Over the widget budget and one job: the phone's rail and dock.
///
/// The phone's replacement for the server rail and the user dock.
///
/// The rail's job was to say, at a glance, which servers want you and where
/// people are — so every row here carries that, in words the rail had no room
/// for. The dock moves to the foot, beside a gear for settings, so mic and
/// deafen stay reachable without leaving the screen you are on.
class ServerSwitcherSheet extends StatelessWidget {
  const ServerSwitcherSheet({super.key});

  static const double _maxWidth = 340;

  void _close(BuildContext context) => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final width = (MediaQuery.sizeOf(context).width * 0.86).clamp(
      0.0,
      _maxWidth,
    );
    final surface = context.select<AppCubit, HomeSurface>(
      (c) => c.state.surface,
    );
    final servers = context.select<ServerCubit, ServerState>((c) => c.state);
    final notifications = context.watch<ServerNotificationsCubit>().state;
    final homeBadge = context.select<CentralDmCubit, int>(
      (c) => c.state.homeBadge,
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: theme.bgSecondary,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(K.radiusCard),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: const BoxDecoration(boxShadow: AppShadows.overlayPane),
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: SafeArea(
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Switch server',
                            style: AppText.dialogTitle.copyWith(
                              color: theme.textPrimary,
                            ),
                          ),
                        ),
                        AppModalHeaderButton(
                          icon: Icons.close,
                          tooltip: 'Close',
                          onPressed: () => _close(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    // Slivers rather than a `ListView`, because the servers
                    // in the middle are reorderable and the rows either side
                    // of them are not.
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                          sliver: SliverList.list(
                            children: [
                              SwitcherHomeRow(
                                selected: surface == HomeSurface.centralDms,
                                unread: homeBadge,
                                onTap: () {
                                  context.read<AppCubit>().setSurface(
                                    HomeSurface.centralDms,
                                  );
                                  _close(context);
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
                                child: Text(
                                  'YOUR SERVERS',
                                  style: AppText.sectionLabel.copyWith(
                                    color: theme.textTertiary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          sliver: SwitcherServerList(
                            servers: servers.servers,
                            selectedServerId: servers.selectedServerId,
                            onHome: surface == HomeSurface.centralDms,
                            notifications: notifications,
                            onOpen: (server) {
                              final app = context.read<AppCubit>();
                              // Back to the server's own list, not whichever
                              // of its halves was open when you left it —
                              // unless you are already on that server.
                              if (server.id != servers.selectedServerId ||
                                  surface == HomeSurface.centralDms) {
                                app.setSurface(HomeSurface.server);
                              }
                              context.read<ServerCubit>().selectServer(server);
                              _close(context);
                            },
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          sliver: SliverToBoxAdapter(
                            child: SwitcherAddRow(
                              onTap: () {
                                final navigator = Navigator.of(context);
                                final serverCubit = context.read<ServerCubit>();
                                final appCubit = context.read<AppCubit>();
                                navigator.pop();
                                showCustomDialog(
                                  context: navigator.context,
                                  build: (_) => MultiBlocProvider(
                                    providers: [
                                      BlocProvider.value(value: serverCubit),
                                      BlocProvider.value(value: appCubit),
                                    ],
                                    child: const AddServerDialog(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const UserDock(showSettings: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
