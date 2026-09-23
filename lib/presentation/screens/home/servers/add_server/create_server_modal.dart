import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/modal_columns.dart';
import '../create_user_dialog.dart';
import 'widgets/credential_group.dart';

/// Over the widget budget and one job: a form: a name and the credentials a
/// server runs on.
///
/// The create step of [AddServerDialog]: a name plus the Supabase and LiveKit
/// credentials the server will run on.
///
/// Wider than the other two steps. Six fields in two credential groups stand
/// beside each other here; picking a mode and pasting an invite have nothing
/// to put in a second column, so the dialog changes width when you reach this
/// step — as it already changes title and subtitle.
class CreateServerModal extends StatefulWidget {
  /// The server exists and the caller is registered on it as admin — not that
  /// the flow is over. Creating a server has one more question to ask.
  final VoidCallback onSuccess;

  final VoidCallback onCancel;

  const CreateServerModal({
    super.key,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<CreateServerModal> createState() => _CreateServerModalState();
}

class _CreateServerModalState extends State<CreateServerModal> {
  final _nameCtrl = TextEditingController();
  final _supabaseUrlCtrl = TextEditingController();
  final _setupSecretCtrl = TextEditingController();
  final _livekitUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _secretKeyCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _supabaseUrlCtrl.text.trim().isNotEmpty &&
      _setupSecretCtrl.text.trim().isNotEmpty &&
      _livekitUrlCtrl.text.trim().isNotEmpty &&
      _apiKeyCtrl.text.trim().isNotEmpty &&
      _secretKeyCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _supabaseUrlCtrl.dispose();
    _setupSecretCtrl.dispose();
    _livekitUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final supabaseUrl = _supabaseUrlCtrl.text.trim();

    final response = await context.read<ServerCubit>().createServer(
      supabaseUrl: supabaseUrl,
      serviceKey: _setupSecretCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      livekitUrl: _livekitUrlCtrl.text.trim(),
      livekitApiKey: _apiKeyCtrl.text.trim(),
      livekitSecretKey: _secretKeyCtrl.text.trim(),
    );

    if (!mounted) return;

    if (!response.success) {
      setState(() {
        _error = response.error;
        _isLoading = false;
      });
      return;
    }

    final inviteCode = response.inviteCode!;

    setState(() => _isLoading = false);

    if (!mounted) return;

    // Register as admin using the single-use invite code generated for us.
    final registered = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CreateUserDialog(supabaseUrl: supabaseUrl, inviteCode: inviteCode),
    );

    if (!mounted) return;

    // No toast: the step this hands off to opens with "Server created" as its
    // title, and saying it twice in two places at once reads as two events.
    if (registered == true) widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Create server',
      subtitle: 'Set up your own server with Supabase and LiveKit',
      maxWidth: K.dialogWidthWide,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MessageBanner(
                message: _error!,
                kind: MessageBannerKind.error,
              ),
            ),

          // Everything below asks for credentials the person filling this in
          // has to go and find. Somebody running the self-hosted stack does
          // not have to: their console generated all four and can make the
          // server itself, handing back an invite link instead. Said here
          // rather than in the docs because this form is exactly where
          // somebody discovers how long it is.
          const MessageBanner(
            message:
                'Running the self-hosted Docker stack? Its console makes '
                'servers for you — none of this to fill in. Open it at '
                'http://localhost:8080, create the server there, and join with '
                'the invite link it gives you.',
            kind: MessageBannerKind.caution,
          ),
          const SizedBox(height: 18),

          AppTextField(
            controller: _nameCtrl,
            label: 'Server name',
            hint: 'My server',
            enabled: !_isLoading,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 18),

          // Two sets of credentials from two different services, which is
          // the longest form in the app — side by side it stops being a
          // scroll.
          ModalColumns(
            children: [
              CredentialGroup(
                label: 'Supabase configuration',
                fields: [
                  AppTextField(
                    controller: _supabaseUrlCtrl,
                    label: 'Supabase URL',
                    hint: 'https://xxxxx.supabase.co',
                    enabled: !_isLoading,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  AppTextField(
                    controller: _setupSecretCtrl,
                    label: 'Service role key',
                    hint: 'Your Supabase service_role key',
                    obscureText: true,
                    enabled: !_isLoading,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ],
              ),
              CredentialGroup(
                label: 'LiveKit Configuration',
                fields: [
                  AppTextField(
                    controller: _livekitUrlCtrl,
                    label: 'LiveKit URL',
                    hint: 'wss://xxxxx.livekit.cloud',
                    enabled: !_isLoading,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  AppTextField(
                    controller: _apiKeyCtrl,
                    label: 'LiveKit API Key',
                    hint: 'API Key',
                    enabled: !_isLoading,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  AppTextField(
                    controller: _secretKeyCtrl,
                    label: 'LiveKit Secret Key',
                    hint: 'Secret key',
                    obscureText: true,
                    enabled: !_isLoading,
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // Back first, then the way on — reading order should run from the way
      // out to the commit, not the other way round.
      actions: [
        AppButton(
          label: 'Back',
          variant: AppButtonVariant.secondary,
          onPressed: _isLoading ? null : widget.onCancel,
        ),
        AppButton(
          label: _isLoading ? 'Creating…' : 'Create server',
          onPressed: _canSubmit && !_isLoading ? _submit : null,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}
