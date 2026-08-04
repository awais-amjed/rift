import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../common/app_panel.dart';
import 'widgets/sidebar_content.dart';

/// Sidebar widget. When pinned, renders the full panel. When unpinned, renders nothing.
class Sidebar extends StatelessWidget {
  final double topPadding;

  const Sidebar({super.key, this.topPadding = 0});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (prev, curr) => prev.isPinned != curr.isPinned,
      builder: (context, appState) {
        if (!appState.isPinned) return const SizedBox.shrink();
        return AppPanel(
          width: K.sidebarWidth,
          child: SidebarContent(isPinned: true, topPadding: topPadding),
        );
      },
    );
  }
}
