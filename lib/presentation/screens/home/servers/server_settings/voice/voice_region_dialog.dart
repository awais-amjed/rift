import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/apis/server_api.dart';
import '../../../../../../data/apis/voice_regions_api.dart';
import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../data/repositories/session_repository.dart';
import '../../../../../../logic/cubits/server_events/server_events_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Add a region, or change the name and address of one.
///
/// A dialog rather than fields edited in place, which is what this was. A
/// region is two values that have to agree — a name people pick from and a
/// box that answers — and editing them in the row meant two separate commits
/// with no way to cancel either: click away from a half-typed address and it
/// was either written or silently dropped, depending on which control had
/// focus. Here the pair is typed, checked and sent once, and Cancel means
/// nothing happened.
///
/// **The default region is the server's own LiveKit**, so its address and
/// key are sent through `update_server` — the URL column and `server_secrets`
/// — and a trigger carries the address into the node; see
/// [ServerApi.updateDefaultVoiceRegion]. Both used to be elsewhere: the
/// address read-only here with a pointer to another page, and the key in a
/// Credentials section under the list. Every region is keyed the same way
/// now, so there is one place to look for any of them.
///
/// **A region signs with its own key pair, and that is not optional.** A
/// shared key sits on every box, so the cheapest VPS in the list would hold
/// the key that mints tokens for the room on every other one; and since the
/// operator has to write *some* key into that box's `livekit.yaml` anyway, a
/// distinct one is the same work. So adding a region asks for both halves and
/// will not proceed without them.
///
/// The key is write-only — nothing here can read what is stored — so on an
/// existing region the fields come up blank and blank means "leave it alone".
/// Filling them is a rotation, one box at a time.
class VoiceRegionDialog extends StatefulWidget {
  /// The region being changed, or null to add one.
  final LiveKitNode? node;

  const VoiceRegionDialog({super.key, this.node});

  /// Whether [value] looks like a LiveKit address, or the sentence saying why
  /// it doesn't.
  ///
  /// Checked here so a typo is a sentence rather than a database constraint —
  /// `livekit_nodes.url` insists on the same shape, and being told by the
  /// server would be both slower and worse worded. Public so the agreement
  /// between the two can be tested.
  static String? checkUrl(String value) {
    if (!RegExp(r'^wss?://[^ ]+$').hasMatch(value)) {
      return 'A LiveKit URL starts with ws:// or wss:// and has no spaces.';
    }
    return null;
  }

  @override
  State<VoiceRegionDialog> createState() => _VoiceRegionDialogState();
}

class _VoiceRegionDialogState extends State<VoiceRegionDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  final _apiKeyCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  LiveKitNode? get _node => widget.node;
  bool get _isEdit => _node != null;

  /// A new region needs its key typed here and now; an existing one needs
  /// nothing but the two fields it already has.
  bool get _canSubmit {
    if (_nameCtrl.text.trim().isEmpty || _urlCtrl.text.trim().isEmpty) {
      return false;
    }
    if (_isEdit) return true;
    return _apiKeyCtrl.text.trim().isNotEmpty &&
        _secretCtrl.text.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _node?.label ?? '');
    _urlCtrl = TextEditingController(text: _node?.url ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  /// Sends only what was actually changed, so renaming a region doesn't
  /// rewrite its address with the same string and wake every client that
  /// watches the node for one.
  Future<({bool success, String? error})> _write(
    VoiceRegionsApi regions,
    ServerApi server,
  ) async {
    final label = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final node = _node;

    // One call, because the region and its key are one act: the server writes
    // both rows in one transaction, so there is no half-made region with no
    // key of its own to explain afterwards.
    if (node == null) {
      return regions.addVoiceRegion(
        label: label,
        url: url,
        apiKey: _apiKeyCtrl.text.trim(),
        secret: _secretCtrl.text.trim(),
      );
    }

    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    if ((apiKey.isEmpty) != (secret.isEmpty)) {
      return (
        success: false,
        error: 'A region needs both an API key and an API secret.',
      );
    }

    if (label != node.label) {
      final renamed = await regions.updateVoiceRegion(
        nodeId: node.id,
        label: label,
      );
      if (!renamed.success) return renamed;
    }
    // The default's address and key live on the server row, so they go
    // together in one call; every other region's are its own two.
    if (node.isDefault) {
      return server.updateDefaultVoiceRegion(
        url: url != node.url ? url : null,
        apiKey: apiKey.isEmpty ? null : apiKey,
        secret: secret.isEmpty ? null : secret,
      );
    }
    if (url != node.url) {
      final moved = await regions.updateVoiceRegion(nodeId: node.id, url: url);
      if (!moved.success) return moved;
    }
    // The fields cannot show what is stored, so both empty means "leave it
    // alone" and both filled is a rotation. There is no third outcome — a
    // region cannot give its key up, because it would then be running on the
    // server's.
    if (apiKey.isEmpty) return (success: true, error: null);
    return regions.setVoiceRegionCredentials(
      nodeId: node.id,
      apiKey: apiKey,
      secret: secret,
    );
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isLoading) return;
    final badUrl = VoiceRegionDialog.checkUrl(_urlCtrl.text.trim());
    if (badUrl != null) {
      setState(() => _error = badUrl);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final session = context.read<SessionRepository>();
    final events = context.read<ServerEventsCubit>();
    final result = await _write(
      VoiceRegionsApi(session: session),
      ServerApi(session: session),
    );
    // The default region's address is the server's own, which every member
    // re-reads on the doorbell; the other regions announce themselves.
    if (result.success && (_node?.isDefault ?? false)) {
      final server = session.selectedServer;
      if (server != null) events.notifyServerChanged(server.id);
    }
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    HelperMethods.showSuccess(
      message: _isEdit ? 'Region updated' : 'Region added',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final isDefault = _node?.isDefault ?? false;
    return AppModal(
      title: _isEdit ? 'Edit region' : 'Add region',
      subtitle: _isEdit ? _node!.label : null,
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _nameCtrl,
            label: 'Region name',
            hint: 'Singapore',
            maxLength: 40,
            enabled: !_isLoading,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _urlCtrl,
            label: 'LiveKit URL',
            hint: 'wss://sg.example.com',
            enabled: !_isLoading,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            isDefault
                ? 'The server\'s own LiveKit. Every call in this region '
                      'connects here, so changing it affects all of them.'
                : 'The address people connect to for calls held here.',
            style: AppText.label.copyWith(color: theme.textTertiary),
          ),
          const SizedBox(height: 16),
          Text(
            _isEdit
                ? 'Leave both blank to keep the current key, or enter a '
                      'new pair to replace it.'
                : 'Use a key pair made just for this region — the one in '
                      'its livekit.yaml. If regions shared one, anyone who '
                      'broke into one server could get into calls in all of '
                      'them.',
            style: AppText.label.copyWith(color: theme.textTertiary),
          ),
          const SizedBox(height: 14),
          AppTextField(
            controller: _apiKeyCtrl,
            label: 'LiveKit API key',
            hint: _isEdit ? 'Leave blank to keep current' : 'APIxxxxxxxx',
            enabled: !_isLoading,
            obscureText: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _secretCtrl,
            label: 'LiveKit API secret',
            hint: _isEdit
                ? 'Leave blank to keep current'
                : 'The secret from its livekit.yaml',
            enabled: !_isLoading,
            obscureText: true,
            onChanged: (_) => setState(() => _error = null),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: _isEdit ? 'Save region' : 'Add region',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
    );
  }
}

/// Opens [VoiceRegionDialog]. It writes through the session, which sits above
/// every route, so it needs nothing handed in.
Future<void> showVoiceRegionDialog(BuildContext context, {LiveKitNode? node}) {
  return showCustomDialog(
    context: context,
    build: (_) => VoiceRegionDialog(node: node),
  );
}
