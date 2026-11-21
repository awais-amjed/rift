import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/stored_clip.dart';
import '../../../../../logic/cubits/clip_history/clip_history_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'clip_history_row.dart';

/// The clips this device keeps, newest first: in the Clips card in a call
/// and under the clipping settings. Reads them when it first shows, with the
/// seed they are sealed under; after that the list follows the library.
class ClipHistoryList extends StatefulWidget {
  /// What a press on a row does: the card closes itself first.
  final void Function(StoredClip clip) onOpen;

  const ClipHistoryList({super.key, required this.onOpen});

  @override
  State<ClipHistoryList> createState() => _ClipHistoryListState();
}

class _ClipHistoryListState extends State<ClipHistoryList> {
  @override
  void initState() {
    super.initState();
    final seed = context.read<VaultCubit>().state.masterSeed;
    if (seed != null) context.read<ClipHistoryCubit>().load(seed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return BlocBuilder<ClipHistoryCubit, ClipHistoryState>(
      builder: (context, state) {
        if (state.clips.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              state.loaded ? 'No clips yet.' : 'Loading…',
              style: AppText.secondary.copyWith(color: theme.textTertiary),
            ),
          );
        }
        final history = context.read<ClipHistoryCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final clip in state.clips)
              ClipHistoryRow(
                key: ValueKey(clip.id),
                clip: clip,
                onOpen: () => widget.onOpen(clip),
                onDelete: () => history.delete(clip.id),
              ),
          ],
        );
      },
    );
  }
}
