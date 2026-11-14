import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/models/models_cubit.dart';
import '../../../../common/download_ring.dart';
import '../../../../common/title_bar/model_download_chip.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// The phone's [ModelDownloadChip]: a phone has no title bar, so its list's
/// top bar carries a ring while a model downloads, and a retry button once
/// one has failed to. A tap on the ring says what is coming down. Nothing
/// once they are all here, which on a fresh install is usually before
/// sign-in ends.
class ModelDownloadMark extends StatelessWidget {
  const ModelDownloadMark({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final state = context.select<ModelsCubit, ModelsState>((c) => c.state);
    final loading = state.loading;
    final failed = state.failed;
    if (loading.isNotEmpty) {
      final percent = (state.fraction * 100).floor();
      return SizedBox.square(
        dimension: K.touchTargetMin,
        child: Tooltip(
          triggerMode: TooltipTriggerMode.tap,
          message:
              'Downloading the ${ModelDownloadChip.names(loading)} '
              '(${ModelDownloadChip.megabytes(loading)}), $percent%. '
              'It is fetched once and kept.',
          child: Center(
            child: DownloadRing(
              fraction: state.fraction,
              color: theme.primary,
              size: K.iconLarge,
            ),
          ),
        ),
      );
    }
    if (failed.isEmpty) return const SizedBox.shrink();
    return SizedBox.square(
      dimension: K.touchTargetMin,
      child: IconButton(
        tooltip:
            "The ${ModelDownloadChip.names(failed)} didn't download. "
            'Tap to try again.',
        onPressed: () => context.read<ModelsCubit>().retryFailed(),
        icon: Icon(
          Icons.refresh_rounded,
          size: K.iconLarge,
          color: theme.statusInk(CustomColors.warning),
        ),
      ),
    );
  }
}
