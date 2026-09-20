import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/services/forwarding/forward_target.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// One destination in the forward picker, with its own checkbox.
///
/// A checkbox rather than a tap-to-send row: forwarding the same thing to
/// two places is the common case, and a list that closed on the first tap
/// would make it two trips through the same menu.
class ForwardTargetRow extends StatelessWidget {
  final ForwardTarget target;
  final bool selected;
  final VoidCallback onTap;

  const ForwardTargetRow({
    super.key,
    required this.target,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(_icon, size: 15, color: theme.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      target.label,
                      style: AppText.row.copyWith(color: theme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      target.context,
                      style: AppText.label.copyWith(
                        fontWeight: FontWeight.w400,
                        color: theme.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 18,
                color: selected ? theme.primary : theme.borderElevated,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (target) {
    ChannelTarget() => Icons.tag_rounded,
    ServerDmTarget() => Icons.alternate_email_rounded,
    CentralDmTarget() => Icons.alternate_email_rounded,
  };
}
