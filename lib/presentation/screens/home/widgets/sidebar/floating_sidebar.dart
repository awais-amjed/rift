import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import 'sidebar_content.dart';

/// Floating sidebar shown when hovered (not pinned).
class FloatingSidebar extends StatelessWidget {
  const FloatingSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: MouseRegion(
        onExit: (_) => context.read<AppCubit>().setIsHovered(false),
        child: const SizedBox(
          width: kSidebarWidth,
          child: SidebarContent(isPinned: false),
        ),
      ),
    );
  }
}
