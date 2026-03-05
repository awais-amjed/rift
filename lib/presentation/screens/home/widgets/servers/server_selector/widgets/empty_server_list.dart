import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../theme/custom_colors.dart';

/// Empty state widget shown when no servers exist.
class EmptyServerList extends StatelessWidget {
  final VoidCallback onAddServer;

  const EmptyServerList({super.key, required this.onAddServer});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          children: [
            const SizedBox(height: 24),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: themeState.bgTertiary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.dns_outlined,
                size: 32,
                color: themeState.textQuaternary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Servers Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: themeState.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Get started by adding your first server',
              style: TextStyle(fontSize: 13, color: themeState.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAddServer,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Your First Server'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CustomColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
