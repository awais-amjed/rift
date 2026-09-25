import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/message_banner.dart';
import '../../server_settings/voice/voice_credentials_section.dart';
import '../../server_settings/voice/voice_regions_section.dart';
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
/// The regions come first and the credential after, because the list is what
/// the page is about and the key and secret are a detail true of all of it.
/// They also behave differently: a region is a row that is added, changed or
/// removed through a dialog and acts the moment that dialog is confirmed,
/// while the credential is two write-only fields on the server row — which is
/// why Save at the foot says what it saves.
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
  final _apiKeyCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    // Only what was filled in is sent: `update_server` leaves out what it
    // isn't given, so a blank field keeps the stored secret rather than
    // clearing it.
    final result = await context.read<ServerCubit>().updateServerDetails(
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
    HelperMethods.showSuccess(message: 'LiveKit credentials updated');
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Voice',
      subtitle: 'Where this server holds calls',
      footer: [
        AppButton(
          label: 'Save credentials',
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
          VoiceRegionsSection(
            serverId: widget.server.id,
            enabled: !_isLoading,
          ),
          const SizedBox(height: 26),
          VoiceCredentialsSection(
            apiKeyCtrl: _apiKeyCtrl,
            secretCtrl: _secretCtrl,
            enabled: !_isLoading,
          ),
        ],
      ),
    );
  }
}
