import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import 'floating_sidebar.dart';
import 'sidebar_content.dart';
import 'sidebar_tab.dart';

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
          width: appState.isPinned ? kSidebarWidth : collapsedWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Sidebar panel (only visible when pinned)
              if (appState.isPinned)
                const SizedBox(
                  width: kSidebarWidth,
                  child: SidebarContent(isPinned: true),
                ),
              // Floating sidebar (shown when hovering and not pinned)
              if (!appState.isPinned && appState.isHovered)
                const FloatingSidebar(),
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
              if (!appState.isPinned && !appState.isHovered) const SidebarTab(),
            ],
          ),
        );
      },
    );
  }
}
