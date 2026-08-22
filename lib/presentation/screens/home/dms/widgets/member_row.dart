import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../theme/app_text.dart';

/// One member in the drop-down. Members with no published chat key are shown
/// but unpickable, with the reason — hiding them reads as them not existing.
class MemberRow extends StatelessWidget {
  final ServerMember member;
  final VoidCallback? onTap;

  const MemberRow({super.key, required this.member, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final enabled = onTap != null;
    final radius = BorderRadius.circular(9);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          hoverColor: themeState.bgHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              spacing: 9,
              children: [
                SquircleAvatar(
                  name: member.displayName,
                  seed: member.id,
                  imageUrl: member.avatarPath,
                  size: 26,
                ),
                Expanded(
                  child: Text(
                    member.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(
                      fontSize: 13,
                      color: themeState.textPrimary,
                    ),
                  ),
                ),
                if (!enabled)
                  Text(
                    'no keys yet',
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: themeState.textQuaternary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
