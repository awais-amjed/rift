import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// The last control in the call's bar: Leave, or — while a stream is being
/// watched — Stop watching.
///
/// Somebody done with a stream reaches for the button at the end of the bar,
/// and that button used to hang up the call. So while anything is watched it
/// puts the streams away instead, and turns back into Leave once nothing is.
/// The way Discord does it, and the reason is the same.
class LeaveButton extends StatelessWidget {
  final bool watching;

  /// Narrow call: tighter padding.
  final bool compact;

  /// Whether the word goes beside the icon.
  final bool showLabel;

  const LeaveButton({
    super.key,
    required this.watching,
    required this.compact,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<LiveKitCubit>();
    // Red either way: it is the button people reach for to be done, and the
    // icon and word say which kind of done. A screen with a cross, as Discord
    // draws it, rather than the handset.
    const ink = CustomColors.onError;
    final radius = BorderRadius.circular(K.radiusRow);
    final label = watching ? 'Stop watching' : 'Leave';

    return Tooltip(
      message: label,
      child: Material(
        color: CustomColors.error,
        borderRadius: radius,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          // Opaque, so hovering deepens the red rather than washing it.
          hoverColor: CustomColors.errorDark,
          onTap: watching ? cubit.stopWatchingAll : cubit.disconnect,
          child: AnimatedSize(
            duration: AppMotion.state,
            curve: AppMotion.settle,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 20,
                vertical: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 8,
                children: [
                  Icon(
                    watching ? Icons.cancel_presentation : Icons.call_end,
                    size: K.iconLarge,
                    color: ink,
                  ),
                  // The word goes when the call is narrow — on a phone, or
                  // beside a wide sidebar. The icon carries it alone there.
                  if (showLabel)
                    Text(
                      label,
                      style: AppText.row.copyWith(
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
