import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../common/app_modal.dart';
import 'widgets/servers/create_user_dialog.dart';
import 'widgets/servers/server_selector/server_selector_dialog.dart';
import 'widgets/sidebar/floating_sidebar.dart';
import 'widgets/sidebar/sidebar.dart';
import 'widgets/participants_grid/participants_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const double _titleBarHeight = K.titleBarHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkServerState());
  }

  void _checkServerState() {
    if (!mounted) return;
    final state = context.read<ServerCubit>().state;

    if (state.servers.isEmpty) {
      _openServerSelector();
    } else if (state.selectedServer?.user == null) {
      _openCreateUser();
    } else {
      // Refresh server details on every startup so fields added after initial
      // save (e.g. supabaseKey) are picked up from the edge function.
      context.read<ServerCubit>().refreshServerDetails();
    }
  }

  void _openServerSelector() {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [BlocProvider.value(value: context.read<ServerCubit>())],
        child: const ServerSelectorDialog(),
      ),
    );
  }

  void _openCreateUser() {
    showCustomDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: const CreateUserDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ServerCubit, ServerState>(
      listener: (context, state) {
        if (state.servers.isEmpty) {
          _openServerSelector();
        } else if (state.selectedServer != null &&
            state.selectedServer!.user == null) {
          _openCreateUser();
        }
      },
      listenWhen: (prev, curr) =>
          prev.servers.length != curr.servers.length ||
          prev.selectedServer?.id != curr.selectedServer?.id ||
          prev.selectedServer?.user != curr.selectedServer?.user,
      child: Scaffold(
        body: BlocBuilder<AppCubit, AppState>(
          buildWhen: (prev, curr) =>
              prev.isPinned != curr.isPinned ||
              prev.titleBarVisible != curr.titleBarVisible,
          builder: (context, appState) {
            final titleBarVisible = appState.titleBarVisible;
            return Stack(
              children: [
                Positioned.fill(
                  top: kIsWeb ? 0 : (titleBarVisible ? _titleBarHeight : 0),
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          if (appState.isPinned)
                            Sidebar(
                              topPadding: kIsWeb
                                  ? 0
                                  : (titleBarVisible
                                        ? 0
                                        : K.titleBarHiddenSidebarPadding),
                            ),
                          const Expanded(child: ParticipantsGrid()),
                        ],
                      ),
                      if (!appState.isPinned)
                        FloatingSidebar(
                          topPadding: kIsWeb
                              ? 0
                              : (titleBarVisible
                                    ? 0
                                    : K.titleBarHiddenSidebarPadding),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
