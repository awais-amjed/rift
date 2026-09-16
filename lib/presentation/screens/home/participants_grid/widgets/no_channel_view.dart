import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/empty_state.dart';

/// The voice stage with no channel selected.
class NoChannelView extends StatelessWidget {
  const NoChannelView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: EmptyState(
            icon: Icons.mic_none_rounded,
            title: 'No channel selected',
            message: 'Pick a voice channel from the sidebar to join.',
          ),
        );
      },
    );
  }
}
