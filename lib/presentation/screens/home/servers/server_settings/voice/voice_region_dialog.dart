import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
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
/// **The default region's address is the server's own LiveKit URL**, so that
/// one field is sent through `update_server` and a trigger carries it into
/// the node — see [ServerCubit.updateDefaultVoiceRegion]. It used to be
/// read-only here, with a line telling the reader to go and find the LiveKit
/// URL field on another page; the field is gone now, and this is where that
/// address is changed.
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
/// Filling them is a rotation, one box at a time. The default region has no
/// fields at all: it *is* the server's LiveKit, so its pair is the server's,
/// set under Credentials on the page behind this one.
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
      return 'A region address starts with ws:// or wss:// and has no spaces.';
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
  Future<({bool success, String? error})> _write(ServerCubit cubit) async {
    final label = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final node = _node;

    // One call, because the region and its key are one act: the server writes
    // both rows in one transaction, so there is no half-made region with no
    // key of its own to explain afterwards.
    if (node == null) {
      return cubit.addVoiceRegion(
        label: label,
        url: url,
        apiKey: _apiKeyCtrl.text.trim(),
        secret: _secretCtrl.text.trim(),
      );
    }

    if (label != node.label) {
      final renamed = await cubit.updateVoiceRegion(
        nodeId: node.id,
        label: label,
      );
      if (!renamed.success) return renamed;
    }
    if (url != node.url) {
      // The address, by whichever route owns it — the default's lives on the
      // server row, every other region's on its own.
      final moved = node.isDefault
          ? await cubit.updateDefaultVoiceRegion(url: url)
          : await cubit.updateVoiceRegion(nodeId: node.id, url: url);
      if (!moved.success) return moved;
    }
    return _writeCredentials(cubit, node);
  }

  /// The key half, which is a different table through a different door.
  ///
  /// Two outcomes and one of them is silence: the fields cannot show what is
  /// stored, so leaving them empty means "leave it alone". Filling them is a
  /// rotation. There is no third outcome — a region cannot give its key up,
  /// because it would then be running on the server's.
  Future<({bool success, String? error})> _writeCredentials(
    ServerCubit cubit,
    LiveKitNode node,
  ) async {
    if (node.isDefault) return (success: true, error: null);

    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    if (apiKey.isEmpty && secret.isEmpty) return (success: true, error: null);
    if (apiKey.isEmpty || secret.isEmpty) {
      return (
        success: false,
        error: 'A region needs both an API key and a secret.',
      );
    }
    return cubit.setVoiceRegionCredentials(
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

    final result = await _write(context.read<ServerCubit>());
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
                ? 'This is the server\'s own LiveKit address — changing it '
                      'moves every call that isn\'t pinned elsewhere.'
                : 'The address people connect to for calls held here.',
            style: AppText.label.copyWith(color: theme.textTertiary),
          ),
          if (!isDefault) ...[
            const SizedBox(height: 16),
            Text(
              _isEdit
                  ? 'This region signs with its own LiveKit key. Type a new '
                        'pair to rotate it, or leave these blank to keep the '
                        'one it has.'
                  : 'Give this region its own API key and secret, set in its '
                        'livekit.yaml and used nowhere else. A key shared with '
                        'your other regions would let a break-in on this box '
                        'mint tokens for calls in all of them.',
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
              label: 'LiveKit secret key',
              hint: _isEdit
                  ? 'Leave blank to keep current'
                  : 'The secret from its livekit.yaml',
              enabled: !_isLoading,
              obscureText: true,
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
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

/// Opens [VoiceRegionDialog] with the cubit it writes through.
///
/// The dialog is a route of its own, so it is outside the manage dialog's
/// providers and has to be handed the cubit rather than reading it from a
/// tree it is no longer in.
Future<void> showVoiceRegionDialog(BuildContext context, {LiveKitNode? node}) {
  final cubit = context.read<ServerCubit>();
  return showCustomDialog(
    context: context,
    build: (_) => BlocProvider.value(
      value: cubit,
      child: VoiceRegionDialog(node: node),
    ),
  );
}
