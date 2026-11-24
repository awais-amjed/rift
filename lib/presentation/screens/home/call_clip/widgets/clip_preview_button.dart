import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/call_clip/clip_preview.dart';
import '../../../../common/app_button.dart';

/// Play and Pause for the trim view's [preview], which Space toggles too.
class ClipPreviewButton extends StatelessWidget {
  final ClipPreview preview;

  const ClipPreviewButton({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preview,
      builder: (context, _) {
        final playing = preview.playing;
        return AppButton(
          label: playing ? 'Pause' : 'Play',
          variant: AppButtonVariant.secondary,
          isLoading: preview.starting,
          icon: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: K.iconButton,
          ),
          onPressed: preview.toggle,
        );
      },
    );
  }
}
