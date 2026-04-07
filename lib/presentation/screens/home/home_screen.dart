import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/channel.dart';
import '../../../data/classes/server_user.dart';
import '../../../data/constants.dart';
import '../../../data/enums/auth_status.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../common/app_modal.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStartup());
  }

  Future<void> _onStartup() async {
    if (!mounted) return;

    final vaultCubit = context.read<VaultCubit>();

    // checkVaultStatus() is async; wait for it to complete before we try to
    // use state.masterSeed, otherwise loginToServer() silently fails with a
    // null-check error and the stale registration token is used forever.
    if (vaultCubit.state.status == AuthStatus.unknown) {
      await vaultCubit.stream
          .firstWhere((s) => s.status != AuthStatus.unknown)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => vaultCubit.state,
          );
      if (!mounted) return;
    }

    final serverState = context.read<ServerCubit>().state;

    if (serverState.servers.isEmpty) {
      _openServerSelector();
    } else {
      // Re-authenticate to each server via challenge-response to get fresh tokens
      await _loginToServers();
    }
  }

  /// Perform challenge-response login for all saved servers.
  Future<void> _loginToServers() async {
    final serverCubit = context.read<ServerCubit>();
    final vaultCubit = context.read<VaultCubit>();

    for (final server in serverCubit.state.servers) {
      final result = await vaultCubit.loginToServer(
        supabaseUrl: server.supabaseUrl,
      );

      if (!mounted) return;

      if (result.success && result.data != null) {
        final data = result.data!;
        final token = data['token'] as String;
        final rawUser = data['user'];
        final rawChannels = data['channels'] as List<dynamic>?;
        final channels = rawChannels
            ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
            .toList();
        final user = rawUser != null
            ? ServerUser.fromJson(rawUser as Map<String, dynamic>)
            : null;

        // Update the server with fresh token and full context
        serverCubit.updateServer(
          server.id,
          token: token,
          user: user,
          channels: channels,
          supabaseKey: data['supabase_key'] as String?,
        );
      }
    }
  }

  void _openServerSelector() {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<VaultCubit>()),
        ],
        child: const ServerSelectorDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ServerCubit, ServerState>(
      listener: (context, state) {
        if (state.servers.isEmpty) {
          _openServerSelector();
        }
      },
      listenWhen: (prev, curr) => prev.servers.length != curr.servers.length,
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
