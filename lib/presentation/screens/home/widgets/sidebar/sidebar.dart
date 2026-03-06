import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import 'widgets/sidebar_content.dart';

/// Sidebar widget. When pinned, renders the full panel. When unpinned, renders nothing.
class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (prev, curr) => prev.isPinned != curr.isPinned,
      builder: (context, appState) {
        if (!appState.isPinned) return const SizedBox.shrink();
        return SizedBox(
          width: kSidebarWidth,
          child: const SidebarContent(isPinned: true),
        );
      },
    );
  }
}
