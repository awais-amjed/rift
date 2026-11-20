import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/byte_format.dart';
import '../../../../common/app_button.dart';

/// Save the selection as a WAV, or take it to the soundboard as an MP3, each
/// with the size it will come to. [onAdd] is null where this person may not
/// add to the call's soundboard, or the call is a DM, and the button is not
/// shown: there is nothing to explain, it is just not theirs to do.
class ClipActions extends StatelessWidget {
  final int wavBytes;
  final int mp3Bytes;
  final bool saving;
  final bool adding;
  final VoidCallback? onSave;
  final VoidCallback? onAdd;

  const ClipActions({
    super.key,
    required this.wavBytes,
    required this.mp3Bytes,
    required this.saving,
    required this.adding,
    required this.onSave,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final busy = saving || adding;
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 10,
      runSpacing: 10,
      children: [
        if (onAdd case final add?)
          AppButton(
            label: 'Add to soundboard · ${humanSize(mp3Bytes)}',
            variant: AppButtonVariant.secondary,
            icon: const Icon(Icons.campaign_rounded, size: K.iconButton),
            isLoading: adding,
            onPressed: busy ? null : add,
          ),
        AppButton(
          label: 'Save · ${humanSize(wavBytes)}',
          icon: const Icon(Icons.download_rounded, size: K.iconButton),
          isLoading: saving,
          onPressed: busy ? null : onSave,
        ),
      ],
    );
  }
}
