import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/screen_share_settings.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/phone_share_publish.dart';
import '../../../../src/rust/api/screenshare/types.dart';
import '../../../common/app_button.dart';
import '../../../theme/theme_context.dart';
import 'widgets/phone_share_options.dart';
import 'widgets/settings_dialog_header.dart';

/// How an Android phone's share goes out, asked before Android's own sheet asks
/// what to share.
///
/// Holds a draft that only reaches [AppCubit] when confirmed, like the desktop's
/// dialog, whose parts it is built from.
class PhoneShareDialog extends StatefulWidget {
  /// What this phone can encode (`PhoneEncoders.codecs`).
  final List<VideoCodec> codecs;

  /// The screen's short side in pixels: the most it can send.
  final int shortSide;

  /// What the call's server allows a share to use, or
  /// [ServerLimits.unlimited].
  final int maxShareMbps;

  const PhoneShareDialog({
    super.key,
    required this.codecs,
    required this.shortSide,
    this.maxShareMbps = ServerLimits.unlimited,
  });

  @override
  State<PhoneShareDialog> createState() => _PhoneShareDialogState();
}

class _PhoneShareDialogState extends State<PhoneShareDialog> {
  late ScreenShareSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = PhoneShare.opening(
      context.read<AppCubit>().state.screenShareSettings,
      shortSide: widget.shortSide,
    );
  }

  /// Remembered at once, even if this share is then cancelled: it is how the
  /// dialog should look next time, not part of this share.
  void _onAdvancedToggled(bool open) {
    setState(() => _draft = _draft.copyWith(showsAdvanced: open));
    final app = context.read<AppCubit>();
    app.setScreenShareSettings(
      app.state.screenShareSettings.copyWith(showsAdvanced: open),
    );
  }

  void _confirm() {
    final settings = _draft.copyWith(phoneSetUp: true);
    context.read<AppCubit>().setScreenShareSettings(settings);
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Dialog(
      backgroundColor: theme.bgElevated,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(K.radiusCard),
        side: BorderSide(color: theme.borderPrimary),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsDialogHeader(onClose: () => Navigator.of(context).pop()),
              Divider(height: 24, color: theme.borderPrimary),
              Flexible(
                child: SingleChildScrollView(
                  child: PhoneShareOptions(
                    settings: _draft,
                    codecs: widget.codecs,
                    resolutions: PhoneShare.resolutionsFor(widget.shortSide),
                    maxShareMbps: widget.maxShareMbps,
                    onChanged: (settings) => setState(() => _draft = settings),
                    onAdvancedToggled: _onAdvancedToggled,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  AppButton(label: 'Start sharing', onPressed: _confirm),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
