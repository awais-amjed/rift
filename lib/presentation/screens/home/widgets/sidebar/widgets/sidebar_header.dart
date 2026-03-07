import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../servers/server_button/server_button.dart';
import '../../servers/server_button/widgets/no_server_button.dart';
import '../../servers/server_selector/server_selector_dialog.dart';

/// Header section of the sidebar with server button and pin toggle.
class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<ServerCubit, ServerState>(
          builder: (context, serverState) {
            final server = serverState.selectedServer;

            return Stack(
              children: [
                // Server button or placeholder
                server != null
                    ? ServerButton(
                        server: server,
                        onTap: () => _openServerSelector(context),
                      )
                    : NoServerButton(onTap: () => _openServerSelector(context)),

                // Pin toggle button
                Positioned(
                  right: 4,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: BlocBuilder<AppCubit, AppState>(
                      buildWhen: (p, c) => p.isPinned != c.isPinned,
                      builder: (context, appState) {
                        return IconButton(
                          onPressed: () => context.read<AppCubit>().setIsPinned(
                            !appState.isPinned,
                          ),
                          icon: Icon(
                            appState.isPinned
                                ? Icons.chevron_left
                                : Icons.push_pin_outlined,
                            size: 20,
                            color: themeState.textTertiary,
                          ),
                          style: IconButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openServerSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<AppCubit>()),
        ],
        child: const ServerSelectorDialog(),
      ),
    );
  }
}
