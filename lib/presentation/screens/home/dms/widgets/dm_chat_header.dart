import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';

/// Header of an open DM conversation: tier icon, peer name, tier note,
/// E2E badge, close.
class DmChatHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const DmChatHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: themeState.textQuaternary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: themeState.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              color: themeState.textQuaternary,
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Messages are end-to-end encrypted',
            child: Icon(
              Icons.lock_outline,
              size: 13,
              color: themeState.textQuaternary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, size: 18, color: themeState.textTertiary),
            tooltip: 'Close conversation',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
