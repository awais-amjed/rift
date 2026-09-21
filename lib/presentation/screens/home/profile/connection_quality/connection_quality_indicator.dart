import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/cubits/voice_stats/voice_stats_cubit.dart';
import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import 'connection_quality_popup.dart';
import 'connection_quality_style.dart';

/// Compact signal-strength line rendered inside the user dock (under the
/// display name) while in a voice channel. Tapping it opens a popup with
/// detailed voice connection stats.
class ConnectionQualityIndicator extends StatefulWidget {
  const ConnectionQualityIndicator({super.key});

  @override
  State<ConnectionQualityIndicator> createState() =>
      _ConnectionQualityIndicatorState();
}

class _ConnectionQualityIndicatorState
    extends State<ConnectionQualityIndicator> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  void _toggle() {
    if (_entry != null) {
      _dismiss();
    } else {
      _show();
    }
  }

  void _show() {
    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;

    // Popup width — clamp so it doesn't bleed off screen
    const popupWidth = 248.0;
    final left = (offset.dx + popupWidth > screenWidth)
        ? screenWidth - popupWidth - 8
        : offset.dx;

    // Anchor the popup bottom just above the indicator bar
    final bottomOffset = MediaQuery.of(context).size.height - offset.dy + 4;

    // Capture blocs from current context before entering overlay
    final voiceStatsCubit = context.read<VoiceStatsCubit>();
    final themeCubit = context.read<ThemeCubit>();

    _entry = OverlayEntry(
      builder: (overlayCtx) => Stack(
        children: [
          // Full-screen dismiss barrier
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismiss,
            ),
          ),
          // Popup anchored above the indicator
          Positioned(
            left: left,
            bottom: bottomOffset,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: voiceStatsCubit),
                BlocProvider.value(value: themeCubit),
              ],
              child: const ConnectionQualityPopup(),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_entry!);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      buildWhen: (prev, curr) => prev.connectionState != curr.connectionState,
      builder: (context, lkState) {
        if (lkState.connectionState != LiveKitConnectionState.connected) {
          return const SizedBox.shrink();
        }

        return BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            return BlocBuilder<VoiceStatsCubit, VoiceStatsState>(
              builder: (context, stats) {
                final color = ConnectionQualityStyle.color(
                  stats.quality,
                  themeState,
                );
                // A measurement is worth showing whoever else is here: the
                // connection to the server is the same one either way, and
                // being the first into a call is when you most want to know
                // it is a good one. Only with nothing to show does the line
                // fall back to saying who is missing.
                final label = stats.rttMs != null
                    ? '${stats.rttMs!.toStringAsFixed(0)} ms · ${ConnectionQualityStyle.label(stats.quality, unknown: 'No data')}'
                    : stats.isAlone
                    ? 'Waiting for others…'
                    : 'Connecting…';
                final measured = stats.rttMs != null;

                return Material(
                  key: _buttonKey,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(K.radiusRow),
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: BorderRadius.circular(K.radiusRow),
                    hoverColor: themeState.bgHover,
                    onTap: measured ? _toggle : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          measured
                              ? ConnectionQualityStyle.icon(stats.quality)
                              : Icons.person_outline,
                          size: 11,
                          color: measured ? color : themeState.textQuaternary,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            style: AppText.label.copyWith(
                              color: themeState.textTertiary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
