import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../logic/cubits/theme/theme_cubit.dart';

/// Empty state shown when no channels exist.
class EmptyChannelsView extends StatelessWidget {
  const EmptyChannelsView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tag, size: 32, color: themeState.textQuaternary),
              const SizedBox(height: 8),
              Text(
                'No channels yet',
                style: TextStyle(fontSize: 13, color: themeState.textTertiary),
              ),
            ],
          ),
        );
      },
    );
  }
}
