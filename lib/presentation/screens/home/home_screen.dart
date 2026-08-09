import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
import '../../../data/enums/auth_status.dart';
import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/server/server_cubit.dart';
import '../../../logic/cubits/vault/vault_cubit.dart';
import '../../common/app_modal.dart';
import '../../common/canvas_backdrop.dart';
import 'main_content/main_content.dart';
import 'servers/add_server/add_server_dialog.dart';
import 'sidebar/floating_sidebar.dart';
import 'sidebar/sidebar.dart';
import 'sidebar/widgets/sidebar_header.dart';

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

    // Wait for checkVaultStatus() to settle before using state.masterSeed —
    // if we proceed while status is still unknown, loginToServer() silently
    // fails and the stale token is used until the next cold start.
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
      _openAddServer();
    } else {
      // Re-authenticate the active server; other servers authenticate lazily.
      await context.read<ServerCubit>().loginSelectedServer();
    }
  }

  /// No servers — on a first run, or after leaving the last one. Straight to
  /// join-or-create: there is nothing to select from.
  void _openAddServer() {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<VaultCubit>()),
        ],
        child: const AddServerDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ServerCubit, ServerState>(
      listener: (context, state) {
        if (state.servers.isEmpty) {
          _openAddServer();
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
            final topPadding = kIsWeb
                ? 0.0
                : (titleBarVisible ? 0.0 : K.titleBarHiddenSidebarPadding);
            return _QuickSwitcherShortcut(
              child: CanvasBackdrop(
                child: Padding(
                  // The title bar is painted above the whole app, so the
                  // workspace steps out from under it; the gutter takes over
                  // when it's hidden.
                  padding: EdgeInsets.only(
                    top: kIsWeb
                        ? K.panelGutter
                        : (titleBarVisible ? _titleBarHeight : K.panelGutter),
                    left: K.panelGutter,
                    right: K.panelGutter,
                    bottom: K.panelGutter,
                  ),
                  child: Stack(
                    children: [
                      Row(
                        children: [
                          // Both are always mounted. Pinning used to add and
                          // remove them, which is why it was a hard cut —
                          // a widget that isn't there can't animate away.
                          // Each hides itself instead, and takes 220ms doing it.
                          //
                          // The gutter lives inside Sidebar: it is the strip
                          // you drag to resize, so it can't be a plain gap.
                          Sidebar(topPadding: topPadding),
                          const Expanded(child: MainContent()),
                        ],
                      ),
                      FloatingSidebar(topPadding: topPadding),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Binds Ctrl/⌘+K to the quick switcher across the whole home screen.
///
/// Both modifiers are bound on every platform rather than branching: a user
/// coming from a Mac will reach for ⌘ on Linux, and nothing else in the app
/// claims either combination.
class _QuickSwitcherShortcut extends StatelessWidget {
  final Widget child;

  const _QuickSwitcherShortcut({required this.child});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            openQuickSwitcher(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            openQuickSwitcher(context),
      },
      child: child,
    );
  }
}
