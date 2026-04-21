import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../common/app_button.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../../../logic/cubits/theme/theme_cubit.dart';

class RemoveServerDialog extends StatelessWidget {
  final String serverName;

  const RemoveServerDialog({super.key, required this.serverName});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Dialog(
          backgroundColor: themeState.bgPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: CustomColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.logout_rounded,
                      color: CustomColors.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Remove Server',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: themeState.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Remove "$serverName" from your server list? Your account on this server will remain intact — you can rejoin with your token at any time.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: themeState.textTertiary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: 'Cancel',
                          variant: AppButtonVariant.secondary,
                          onPressed: () => Navigator.of(context).pop(false),
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: AppButton(
                          label: 'Remove',
                          variant: AppButtonVariant.danger,
                          icon: const Icon(
                            Icons.logout_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                          expanded: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
