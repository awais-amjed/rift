import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';

/// Button to start watching a screenshare stream
class WatchStreamButton extends StatelessWidget {
  final VoidCallback onTap;

  const WatchStreamButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Center(
          child: Material(
            color: CustomColors.primary.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
            elevation: 4,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.play_circle_filled,
                      size: 28,
                      color: Colors.white,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Watch Stream',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
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
