import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../profile/user_profile.dart';
import 'sidebar_channel_list.dart';
import 'sidebar_header.dart';
import 'sidebar_actions.dart';

const double kSidebarWidth = 280;

/// The main content of the sidebar, used both in pinned and floating modes.
class SidebarContent extends StatelessWidget {
  final bool isPinned;
  final double topPadding;

  const SidebarContent({
    super.key,
    required this.isPinned,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          decoration: BoxDecoration(
            color: themeState.sidebarBg,
            border: Border(right: BorderSide(color: themeState.borderPrimary)),
            boxShadow: isPinned
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: themeState.isDarkTheme ? 0.4 : 0.12,
                      ),
                      blurRadius: 24,
                      offset: const Offset(4, 0),
                    ),
                  ],
          ),
          child: Column(
            children: [
              SizedBox(height: topPadding),
              SidebarHeader(),
              SidebarActions(),
              SidebarChannelList(),
              UserProfile(),
            ],
          ),
        );
      },
    );
  }
}
