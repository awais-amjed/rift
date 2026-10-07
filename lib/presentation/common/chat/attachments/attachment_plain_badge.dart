import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';

/// Says a file was sent unencrypted: the server holds its bytes, not a
/// ciphertext. The same pill as `MessageOriginBadge`, and like it always
/// shown, with no setting. The message around it is still sealed, so the
/// pill sits on the file rather than the message.
class AttachmentPlainBadge extends StatelessWidget {
  const AttachmentPlainBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final ink = context.theme.statusInk(CustomColors.warning);
    return Tooltip(
      message: 'Sent unencrypted — the server can see this file.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: CustomColors.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(K.radiusRow),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 3,
          children: [
            Icon(Icons.lock_open_rounded, size: K.iconTiny, color: ink),
            Text('NOT ENCRYPTED', style: AppText.roleChip.copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}
