import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';

/// Sidebar row that opens the Home (Direct Messages) surface in the center
/// pane — both central and server DMs live there.
class HomeDmButton extends StatelessWidget {
  const HomeDmButton({super.key});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (prev, curr) => prev.homeViewOpen != curr.homeViewOpen,
      builder: (context, appState) {
        final selected = appState.homeViewOpen;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
            color: selected ? themeState.channelActiveBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              hoverColor: themeState.bgHover,
              onTap: () =>
                  context.read<AppCubit>().setHomeViewOpen(!selected),
              child: Container(
                decoration: selected
                    ? BoxDecoration(
                        border:
                            Border.all(color: themeState.channelActiveBorder),
                        borderRadius: BorderRadius.circular(10),
                      )
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.forum_outlined,
                      size: 17,
                      color: selected
                          ? themeState.primary
                          : themeState.textQuaternary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Direct Messages',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: selected
                              ? themeState.channelActiveText
                              : themeState.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
