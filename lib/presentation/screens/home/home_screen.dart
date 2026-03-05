import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/server/server_cubit.dart';
import 'widgets/profile/create_user_dialog.dart';
import 'widgets/servers/server_selector_dialog.dart';
import 'widgets/sidebar/sidebar.dart';
import 'widgets/participants/video_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
    }
  }

  void _openServerSelector() {
    showDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [BlocProvider.value(value: context.read<ServerCubit>())],
        child: const ServerSelectorDialog(),
      ),
    );
  }

  void _openCreateUser() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: const CreateUserDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen for server state changes to auto-open dialogs
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
        body: Row(
          children: const [
            Sidebar(),
            Expanded(child: VideoGrid()),
          ],
        ),
      ),
    );
  }
}
