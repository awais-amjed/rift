import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';

/// A square control in a panel header.
///
/// [isActive] keeps a standing fill for toggles that are currently on, so the
/// members panel being open is legible from the button itself rather than only
/// from the panel's presence.
class ChatHeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final VoidCallback onTap;

  const ChatHeaderButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final radius = BorderRadius.circular(9);

        return Tooltip(
          message: tooltip,
          waitDuration: const Duration(milliseconds: 400),
          child: Material(
            color: isActive ? themeState.bgHover : Colors.transparent,
            borderRadius: radius,
            child: InkWell(
              borderRadius: radius,
              hoverColor: themeState.bgActive,
              onTap: onTap,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(
                  icon,
                  size: 17,
                  color: isActive
                      ? themeState.textSecondary
                      : themeState.textTertiary,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
