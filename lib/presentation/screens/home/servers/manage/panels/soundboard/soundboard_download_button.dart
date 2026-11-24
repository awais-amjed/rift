import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../../data/classes/soundboard_sound.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../../logic/cubits/soundboard/soundboard_cubit.dart';
import '../../../../../../../logic/helper_methods.dart';
import '../../../../../../../logic/services/soundboard_file_name.dart';
import '../../../../../../common/chat/attachments/attachment_download.dart';
import '../../../../../../theme/theme_context.dart';

/// Saves one clip from the board to wherever the person picks, under its
/// name on the board.
///
/// The bytes come first and the save dialog after, so a clip that cannot be
/// fetched says so at once rather than after a place was chosen for it.
class SoundboardDownloadButton extends StatefulWidget {
  final SoundboardSound sound;

  const SoundboardDownloadButton({super.key, required this.sound});

  @override
  State<SoundboardDownloadButton> createState() =>
      _SoundboardDownloadButtonState();
}

class _SoundboardDownloadButtonState extends State<SoundboardDownloadButton> {
  bool _fetching = false;

  Future<void> _download() async {
    setState(() => _fetching = true);
    final bytes = await context.read<SoundboardCubit>().bytesOf(widget.sound);
    if (!mounted) return;
    setState(() => _fetching = false);
    if (bytes == null) {
      HelperMethods.showError(error: "Couldn't download that clip.");
      return;
    }
    await saveToDisk(
      context,
      soundboardFileName(widget.sound.name, bytes),
      bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Download',
      icon: const Icon(Icons.download_rounded, size: K.iconButton),
      color: context.theme.textTertiary,
      onPressed: _fetching ? null : _download,
    );
  }
}
