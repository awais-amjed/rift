import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/classes/model_file.dart';
import '../../../data/constants.dart';
import '../../../logic/cubits/models/models_cubit.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';
import '../download_ring.dart';
import '../status_chip.dart';

/// A model downloading beside the window controls, with how far it has come,
/// or one that failed to, which pressing tries again. Nothing once they are
/// all here.
///
/// The first start fetches the picture safety model while the person signs
/// in, and a noise model comes down when it is first chosen; without this,
/// the wait for either was invisible.
class ModelDownloadChip extends StatelessWidget {
  const ModelDownloadChip({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.select<ModelsCubit, ModelsState>((c) => c.state);
    final loading = state.loading;
    final failed = state.failed;
    final StatusChip chip;
    if (loading.isNotEmpty) {
      final fraction = state.fraction;
      chip = StatusChip(
        icon: Icons.downloading_rounded,
        leading: (ink) => DownloadRing(fraction: fraction, color: ink),
        label: loading.length == 1
            ? 'Downloading model ${(fraction * 100).floor()}%'
            : 'Downloading ${loading.length} models '
                  '${(fraction * 100).floor()}%',
        color: context.theme.primary,
        tooltip:
            'Rift is downloading its ${names(loading)} '
            '(${megabytes(loading)}). It is fetched once and kept.',
      );
    } else if (failed.isNotEmpty) {
      chip = StatusChip(
        icon: Icons.refresh_rounded,
        label: failed.length == 1
            ? "Model didn't download"
            : "${failed.length} models didn't download",
        color: CustomColors.warning,
        tooltip:
            "Rift couldn't download its ${names(failed)}. "
            'Click to try again.',
        onTap: () => context.read<ModelsCubit>().retryFailed(),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: K.titleBarChipMaxWidth),
        child: chip,
      ),
    );
  }

  /// The models' names in a sentence, for the phone's mark too.
  static String names(List<ModelFile> files) {
    final names = [for (final f in files) f.name];
    return names.length == 1
        ? names.single
        : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  /// The models' size together, for the phone's mark too.
  static String megabytes(List<ModelFile> files) {
    final bytes = files.fold<int>(0, (sum, f) => sum + f.size);
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}
