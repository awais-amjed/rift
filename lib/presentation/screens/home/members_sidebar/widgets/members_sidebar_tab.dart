import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../common/edge_tab.dart';
import '../../../../theme/app_motion.dart';

/// Brings the member list back once it has been hidden.
///
/// It used to leave a 42px strip behind with a button in it, which is a lot of
/// window to keep for one icon. The panel goes away entirely now, and this is
/// what is left to get it back — the same tab the left sidebar uses, on the
/// other edge.
///
/// Stays in the tree while the list is open so it has something to animate
/// from, sliding out through the right edge rather than blinking away.
class MembersSidebarTab extends StatelessWidget {
  const MembersSidebarTab({super.key});

  @override
  Widget build(BuildContext context) {
    final open = context.select<AppCubit, bool>(
      (cubit) => cubit.state.membersSidebarOpen,
    );

    return IgnorePointer(
      ignoring: open,
      child: AnimatedSlide(
        duration: K.sidebarMotion,
        curve: AppMotion.panel,
        offset: open ? const Offset(1, 0) : Offset.zero,
        child: AnimatedOpacity(
          duration: K.sidebarMotion,
          curve: AppMotion.panel,
          opacity: open ? 0 : 1,
          child: EdgeTab(
            side: EdgeTabSide.right,
            tooltip: 'Show members',
            onTap: () => context.read<AppCubit>().toggleMembersSidebar(),
          ),
        ),
      ),
    );
  }
}
