import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/theme/theme_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../common/app_title_bar.dart';
import 'widgets/servers/create_user_dialog.dart';
import 'widgets/servers/server_selector/server_selector_dialog.dart';
import 'widgets/sidebar/sidebar.dart';
import 'widgets/participants_grid/participants_grid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _titleBarVisible = true;

  // When hidden, show it again as an overlay while cursor is in the top zone.
  bool _titleBarOverlay = false;

  static const double _titleBarHeight = 40;

  // Invisible hot-zone height at the top of the screen that triggers the overlay.
  static const double _hotZoneHeight = 40;

  void _onMouseMove(PointerEvent event) {
    if (_titleBarVisible) return;
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
          buildWhen: (prev, curr) => prev.isPinned != curr.isPinned,
          builder: (context, appState) {
            return MouseRegion(
              onHover: _onMouseMove,
              // When cursor leaves the window entirely, close the overlay.
              onExit: (_) {
                if (_titleBarOverlay) {
                  setState(() => _titleBarOverlay = false);
                }
              },
              child: Stack(
                children: [
                  // ── Main content ──────────────────────────────────────
                  Positioned.fill(
                    top: _titleBarVisible ? _titleBarHeight : 0,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            if (appState.isPinned) const Sidebar(),
                            const Expanded(child: ParticipantsGrid()),
                          ],
                        ),
                        if (!appState.isPinned)
                          Positioned(
                            left: 12,
                            top: 12,
                            child: _HamburgerButton(
                              onTap: () =>
                                  context.read<AppCubit>().setIsPinned(true),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // ── Title bar (pinned or overlay) ─────────────────────
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    top: (_titleBarVisible || _titleBarOverlay)
                        ? 0
                        : -_titleBarHeight,
                    left: 0,
                    right: 0,
                    height: _titleBarHeight,
                    child: AppTitleBar(
                      height: _titleBarHeight,
                      pinned: _titleBarVisible,
                      onHide: () => setState(() {
                        _titleBarVisible = false;
                        _titleBarOverlay = false;
                      }),
                      onShow: () => setState(() {
                        _titleBarVisible = true;
                        _titleBarOverlay = false;
                      }),
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

class _HamburgerButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HamburgerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: themeState.bgSecondary,
          borderRadius: BorderRadius.circular(10),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.3),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.menu,
                size: 20,
                color: themeState.textSecondary,
              ),
            ),
          ),
        );
      },
    );
  }
}
