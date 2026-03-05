import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../theme/custom_colors.dart';
import 'channel_list.dart';
import 'create_channel_dialog.dart';
import 'invite_modal.dart';
import 'server_action_bar.dart';
import 'server_button.dart';
import 'server_selector_dialog.dart';
import 'user_profile.dart';

const double _kSidebarWidth = 280;

/// Collapsible sidebar with server selector, channel list, and user profile.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (prev, curr) =>
          prev.isPinned != curr.isPinned || prev.isHovered != curr.isHovered,
      builder: (context, appState) {
        // When collapsed, keep 24px width for hover zone and tab
        const collapsedWidth = 24.0;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: appState.isPinned ? _kSidebarWidth : collapsedWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Sidebar panel (only visible when pinned)
              if (appState.isPinned)
                SizedBox(
                  width: _kSidebarWidth,
                  child: _SidebarContent(isPinned: true),
                ),
              // Floating sidebar (shown when hovering and not pinned)
              if (!appState.isPinned && appState.isHovered)
                _FloatingSidebar(isHovered: appState.isHovered),
              // Always show hover trigger zone when not pinned
              if (!appState.isPinned)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: collapsedWidth,
                  child: MouseRegion(
                    onEnter: (_) => context.read<AppCubit>().setIsHovered(true),
                    cursor: SystemMouseCursors.resizeRight,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              // Visual tab indicator when sidebar is hidden
              if (!appState.isPinned && !appState.isHovered) _SidebarTab(),
            ],
          ),
        );
      },
    );
  }
}

/// Floating sidebar shown when hovered (not pinned).
class _FloatingSidebar extends StatelessWidget {
  final bool isHovered;

  const _FloatingSidebar({required this.isHovered});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: MouseRegion(
        onExit: (_) => context.read<AppCubit>().setIsHovered(false),
        child: SizedBox(
          width: _kSidebarWidth,
          child: _SidebarContent(isPinned: false),
        ),
      ),
    );
  }
}

class _SidebarContent extends StatelessWidget {
  final bool isPinned;

  const _SidebarContent({required this.isPinned});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? CustomColors.sidebarBgDark
        : CustomColors.sidebarBgLight;
    final borderColor = isDark
        ? CustomColors.borderPrimaryDark
        : CustomColors.borderPrimaryLight;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(right: BorderSide(color: borderColor)),
        boxShadow: isPinned
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(4, 0),
                ),
              ],
      ),
      child: Column(
        children: [
          _ServerHeader(),
          _ServerActionsBar(),
          _ChannelListWrapper(),
          const UserProfile(),
        ],
      ),
    );
  }
}

class _ServerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTertiary = isDark
        ? CustomColors.textTertiaryDark
        : CustomColors.textTertiaryLight;

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
                            : Icons.chevron_right,
                        size: 20,
                        color: textTertiary,
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

class _ServerActionsBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      builder: (context, serverState) {
        final server = serverState.selectedServer;
        final permissions = server?.user?.permissions;
        if (permissions == null) return const SizedBox.shrink();

        final showAny =
            permissions.canCreateTokens || permissions.isChannelManager;
        if (!showAny) return const SizedBox.shrink();

        return ServerActionBar(
          permissions: permissions,
          onInvite: () => showDialog(
            context: context,
            builder: (_) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: context.read<ServerCubit>()),
                BlocProvider.value(value: context.read<AppCubit>()),
              ],
              child: const InviteModal(),
            ),
          ),
          onCreateChannel: () => showDialog(
            context: context,
            builder: (_) => MultiBlocProvider(
              providers: [
                BlocProvider.value(value: context.read<ServerCubit>()),
                BlocProvider.value(value: context.read<AppCubit>()),
              ],
              child: const CreateChannelDialog(),
            ),
          ),
        );
      },
    );
  }
}

class _ChannelListWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      builder: (context, serverState) {
        final channels = serverState.selectedServer?.channels ?? [];

        return BlocBuilder<AppCubit, AppState>(
          buildWhen: (prev, curr) =>
              prev.selectedChannelId != curr.selectedChannelId,
          builder: (context, appState) {
            return ChannelList(
              channels: channels,
              selectedChannelId: appState.selectedChannelId,
              onChannelSelect: (id) =>
                  context.read<AppCubit>().setSelectedChannelId(id),
            );
          },
        );
      },
    );
  }
}

/// Visual tab indicator that appears when sidebar is hidden
class _SidebarTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? CustomColors.bgSecondaryDark
        : CustomColors.bgSecondaryLight;
    final iconColor = isDark
        ? CustomColors.textSecondaryDark
        : CustomColors.textSecondaryLight;

    return Positioned(
      left: 0,
      top: 12,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => context.read<AppCubit>().setIsPinned(true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
              border: Border.all(
                color: isDark
                    ? CustomColors.borderPrimaryDark
                    : CustomColors.borderPrimaryLight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                  blurRadius: 8,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Icon(Icons.chevron_right, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}
