import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/message_banner.dart';
import '../../server_settings/widgets/server_livekit_section.dart';
import '../../server_settings/widgets/server_voice_regions_section.dart';
import '../widgets/manage_panel.dart';

/// Where this server's calls are held: the LiveKit it signs tokens for, and
/// the regions a channel may be pinned to.
///
/// Its own page rather than half of Overview, which is where it started. One
/// LiveKit was a URL and two secret fields, and sat under the server's name
/// happily enough; regions made it a list that grows, with its own errors and
/// its own load figures, and Overview became a page about voice infrastructure
/// with the server's name at the top of it.
///
/// The two halves save differently and are stacked rather than columned for
/// that reason. The fields above are the server row and wait for Save; the
/// list below is rows of its own and acts immediately — so the list has to
/// read as *under* the fields it borrows the key and secret from, not beside
/// them.
///
/// Takes the server rather than reading the selection, because the dialog
/// opens from the rail's menu for any server, including one you are not
/// looking at. The write below names it; the region list says why it is the
/// one thing here that still needs the server open.
class VoicePanel extends StatefulWidget {
  final Server server;

  const VoicePanel({super.key, required this.server});

  @override
  State<VoicePanel> createState() => _VoicePanelState();
}

class _VoicePanelState extends State<VoicePanel> {
  late final TextEditingController _livekitUrlCtrl;
  final _apiKeyCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _livekitUrlCtrl = TextEditingController(
      text: widget.server.livekitUrl ?? '',
    );
  }

  @override
  void dispose() {
    _livekitUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final url = _livekitUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    // Only what was filled in is sent: `update_server` leaves out what it
    // isn't given, so a blank secret keeps the stored one and a blank URL
    // doesn't unset the address.
    final result = await context.read<ServerCubit>().updateServerDetails(
      livekitUrl: url.isEmpty ? null : url,
      livekitApiKey: apiKey.isEmpty ? null : apiKey,
      livekitSecretKey: secret.isEmpty ? null : secret,
      serverId: widget.server.id,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _error = result.error ?? 'Failed to update server';
        _isLoading = false;
      });
      return;
    }

    // The secret fields are cleared because the server has them now, and a
    // form that kept showing a secret is one that pastes it again on the next
    // Save.
    _apiKeyCtrl.clear();
    _secretCtrl.clear();
    setState(() => _isLoading = false);
    HelperMethods.showSuccess(message: 'Voice settings updated');
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Voice',
      subtitle: 'Where this server holds calls',
      footer: [
        AppButton(
          label: 'Save',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error case final error?) ...[
            MessageBanner(message: error, kind: MessageBannerKind.error),
            const SizedBox(height: 18),
          ],
          ServerLiveKitSection(
            livekitUrlCtrl: _livekitUrlCtrl,
            apiKeyCtrl: _apiKeyCtrl,
            secretCtrl: _secretCtrl,
            enabled: !_isLoading,
          ),
          const SizedBox(height: 26),
          ServerVoiceRegionsSection(
            serverId: widget.server.id,
            enabled: !_isLoading,
          ),
        ],
      ),
    );
  }
}
