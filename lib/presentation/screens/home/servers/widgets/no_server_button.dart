import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Placeholder shown when no server is selected.
class NoServerButton extends StatelessWidget {
  final VoidCallback onTap;

  const NoServerButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        hoverColor: themeState.bgHover,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: themeState.bgTertiary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.dns_outlined,
                  size: K.iconRow,
                  color: themeState.textQuaternary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'No server selected',
                      style: AppText.strong.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                    Text(
                      'Click to add',
                      style: AppText.label.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
