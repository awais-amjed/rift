import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/empty_state.dart';

/// The voice stage while the LiveKit connection is being made.
class ConnectingView extends StatelessWidget {
  const ConnectingView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          color: themeState.bgSecondary,
          child: const EmptyState(
            icon: Icons.sync_rounded,
            busy: true,
            title: 'Connecting…',
            message: 'Joining the voice channel.',
          ),
        );
      },
    );
  }
}
