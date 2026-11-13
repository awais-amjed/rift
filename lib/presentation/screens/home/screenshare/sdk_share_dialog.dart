import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/classes/screen_share_settings.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/web_share_publish.dart';
import '../../../../src/rust/api/screenshare/types.dart';
import '../../../common/app_button.dart';
import '../../../theme/theme_context.dart';
import 'widgets/sdk_share_options.dart';
import 'widgets/settings_dialog_header.dart';

/// How a share the SDK captures goes out, an Android phone's or a browser's,
/// asked before the system's own sheet or picker asks what to share.
///
/// Holds a draft that only reaches [AppCubit] when confirmed, like the desktop's
/// dialog, whose parts it is built from.
class SdkShareDialog extends StatefulWidget {
  /// What this device can encode (`PhoneEncoders.codecs`).
  final List<VideoCodec> codecs;

  /// What Auto sends here.
  final VideoCodec autoCodec;

  /// The picture heights offered.
  final List<int> resolutions;

  /// The rates offered (`PhoneShare.frameRatesFor`, [WebShare.frameRates]).
  final List<int> frameRates;

  /// The saved settings as this device opens them (`PhoneShare.opening`,
  /// [WebShare.opening]).
  final ScreenShareSettings Function(ScreenShareSettings saved) opening;

  /// Whether the share can carry sound: a browser's.
  final bool offersSound;

  /// What the call's server allows a share to use, or
  /// [ServerLimits.unlimited].
  final int maxShareMbps;

  const SdkShareDialog({
    super.key,
    required this.codecs,
    required this.autoCodec,
    required this.resolutions,
    required this.frameRates,
    required this.opening,
    this.offersSound = false,
    this.maxShareMbps = ServerLimits.unlimited,
  });

  @override
  State<SdkShareDialog> createState() => _SdkShareDialogState();
}

class _SdkShareDialogState extends State<SdkShareDialog> {
  late ScreenShareSettings _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.opening(context.read<AppCubit>().state.screenShareSettings);
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
                  child: SdkShareOptions(
                    settings: _draft,
                    codecs: widget.codecs,
                    autoCodec: widget.autoCodec,
                    offersSound: widget.offersSound,
                    resolutions: widget.resolutions,
                    frameRates: widget.frameRates,
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
