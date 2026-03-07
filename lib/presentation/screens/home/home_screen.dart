import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../common/app_title_bar.dart';
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
  // When hidden, show it again as an overlay while cursor is in the top zone.
  bool _titleBarOverlay = false;

  static const double _titleBarHeight = 40;

  // Invisible hot-zone height at the top of the screen that triggers the overlay.
  static const double _hotZoneHeight = 40;

  void _onMouseMove(PointerEvent event, bool titleBarVisible) {
    if (titleBarVisible) return;
    final nearTop = event.localPosition.dy <= _hotZoneHeight;
    if (nearTop != _titleBarOverlay) {
      setState(() => _titleBarOverlay = nearTop);
    }
  }

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
            return MouseRegion(
              onHover: (e) => _onMouseMove(e, titleBarVisible),
              onExit: (_) {
                if (_titleBarOverlay) {
                  setState(() => _titleBarOverlay = false);
                }
              },
              child: Stack(
                children: [
                  // ── Main content ──────────────────────────────────────
                  Positioned.fill(
                    top: titleBarVisible ? _titleBarHeight : 0,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            if (appState.isPinned)
                              Sidebar(topPadding: titleBarVisible ? 0 : 20),
                            const Expanded(child: ParticipantsGrid()),
                          ],
                        ),
                        if (!appState.isPinned)
                          FloatingSidebar(topPadding: titleBarVisible ? 0 : 20),
                      ],
                    ),
                  ),

                  // ── Title bar (pinned or overlay) ─────────────────────
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    top: (titleBarVisible || _titleBarOverlay)
                        ? 0
                        : -_titleBarHeight,
                    left: 0,
                    right: 0,
                    height: _titleBarHeight,
                    child: AppTitleBar(
                      height: _titleBarHeight,
                      pinned: titleBarVisible,
                      onHide: () {
                        context.read<AppCubit>().setTitleBarVisible(false);
                        setState(() => _titleBarOverlay = false);
                      },
                      onShow: () {
                        context.read<AppCubit>().setTitleBarVisible(true);
                        setState(() => _titleBarOverlay = false);
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
