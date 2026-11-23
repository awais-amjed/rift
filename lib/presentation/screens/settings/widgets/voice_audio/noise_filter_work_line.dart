import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/noise_filter_work.dart';
import '../../../../../data/enums/noise_suppression.dart';
import '../../../../../logic/cubits/models/models_cubit.dart';
import '../../../../../logic/services/noise_filter.dart';
import '../../../../common/download_ring.dart';
import '../../../../common/loading_dots.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// What the noise suppression choice is waiting on, in place of the line
/// that says what the choice suits, so a pick that takes a moment is not
/// taken for one that did nothing. While a model downloads, or after it
/// failed to, it also says what the microphone gets meanwhile.
class NoiseFilterWorkLine extends StatelessWidget {
  final NoiseFilterWork work;

  /// The choice being waited on.
  final NoiseSuppression mode;

  /// What the microphone gets meanwhile ([NoiseFilter.inEffect]).
  final NoiseSuppression inEffect;

  const NoiseFilterWorkLine({
    super.key,
    required this.work,
    required this.mode,
    required this.inEffect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final style = AppText.secondary.copyWith(color: theme.textTertiary);
    final meanwhile = inEffect == mode || inEffect == NoiseSuppression.off
        ? ''
        : ' · ${inEffect.label} for now';
    return switch (work) {
      NoiseFilterWork.downloadingModel => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Progress(color: theme.textTertiary),
          const SizedBox(width: 6),
          Flexible(
            child: _Downloading(
              label: 'Downloading ${mode.label}',
              meanwhile: meanwhile,
              style: style,
            ),
          ),
        ],
      ),
      NoiseFilterWork.modelUnavailable => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => context.read<ModelsCubit>().retryFailed(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: K.iconTiny,
                color: theme.statusInk(CustomColors.warning),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  "${mode.label} didn't download$meanwhile",
                  style: style,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Try again',
                style: AppText.secondary.copyWith(
                  color: theme.accentBright,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      NoiseFilterWork.modelCannotRun => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: K.iconTiny,
            color: theme.statusInk(CustomColors.warning),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              "${mode.label} can't run on this computer"
              '${inEffect == mode ? '' : ' · ${inEffect.label} instead'}',
              style: style,
            ),
          ),
        ],
      ),
      _ => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LoadingDots(color: theme.textTertiary, dotSize: 3),
          const SizedBox(width: 6),
          Text(switch (work) {
            NoiseFilterWork.loadingModel => 'Loading ${mode.label}…',
            _ => 'Starting noise suppression…',
          }, style: style),
        ],
      ),
    };
  }
}

/// How far the chosen model's files have come, read from the downloads
/// alone so that only the ring and figure redraw as they tick.
double _fraction(ModelsCubit cubit) =>
    cubit.state.fractionOf(NoiseFilter.awaitedFiles);

class _Progress extends StatelessWidget {
  final Color color;

  const _Progress({required this.color});

  @override
  Widget build(BuildContext context) => DownloadRing(
    fraction: context.select<ModelsCubit, double>(_fraction),
    color: color,
  );
}

class _Downloading extends StatelessWidget {
  final String label;
  final String meanwhile;
  final TextStyle style;

  const _Downloading({
    required this.label,
    required this.meanwhile,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (context.select<ModelsCubit, double>(_fraction) * 100)
        .floor();
    return Text('$label $percent%$meanwhile', style: style);
  }
}
