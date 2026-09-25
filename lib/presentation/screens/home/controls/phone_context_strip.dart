import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../common/status_chip.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';
import '../profile/person/verification/show_channel_encryption.dart';
import 'context_strip.dart';

/// The strip on a phone, where the call is a page of its own.
///
/// It leads with the way back to the list — pointing down, because leaving the
/// page tucks the call away into the bar over the list rather than ending it.
/// The time moves under the name beside the server, since there is no room at
/// the far end once the encryption claim is there, and the head count goes:
/// the tiles under the strip are the count.
class PhoneContextStrip extends StatelessWidget {
  final String channelName;
  final String? serverName;
  final Widget elapsed;

  const PhoneContextStrip({
    super.key,
    required this.channelName,
    required this.serverName,
    required this.elapsed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final navigator = Navigator.of(context);
    return Container(
      height: ContextStrip.heightFor(compact: true),
      padding: const EdgeInsets.fromLTRB(4, 0, 12, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.borderPrimary)),
      ),
      child: Row(
        spacing: 6,
        children: [
          SizedBox.square(
            dimension: K.touchTargetMin,
            child: navigator.canPop()
                ? IconButton(
                    tooltip: 'Back to the list',
                    onPressed: navigator.maybePop,
                    icon: Icon(
                      Icons.expand_more_rounded,
                      size: 24,
                      color: theme.textSecondary,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Icon(
                      Icons.volume_up_rounded,
                      size: K.iconRow,
                      color: theme.accentBright,
                    ),
                    Flexible(
                      child: Text(
                        channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.panelTitle.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    elapsed,
                    if (serverName != null)
                      Flexible(
                        child: Text(
                          '  ·  $serverName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.figure.copyWith(
                            color: theme.textTertiary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          StatusChip(
            icon: Icons.lock_outline,
            label: 'Encrypted',
            color: CustomColors.success,
            tooltip: StatusChip.encryptedVerifyTooltip,
            onTap: () => showCallEncryption(
              context,
              channelName: channelName,
              participants: context.read<AppCubit>().state.participants,
            ),
          ),
        ],
      ),
    );
  }
}
