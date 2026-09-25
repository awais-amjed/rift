import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../common/checkbox_row.dart';
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
/// **A region may sign with its own key pair**, and the box that offers it is
/// the point of the whole feature: a shared key sits on every box, so the
/// cheapest VPS in the list holds the key that mints tokens for the room on
/// every other one. Left off, the region uses the server's pair, which is
/// what a single-LiveKit server has always done and what the default region
/// always does — it is refused a key of its own, so the box is not drawn for
/// it. The key is write-only: this can say a region *has* one, never what it
/// is, so the fields come up blank on a region that already does.
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

  /// Whether this region should sign with a key of its own. Starts true for a
  /// region that already has one, so that saving without touching anything
  /// leaves it alone rather than taking its key away.
  late bool _ownKey;

  bool _isLoading = false;
  String? _error;

  LiveKitNode? get _node => widget.node;
  bool get _isEdit => _node != null;

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty && _urlCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: _node?.label ?? '');
    _urlCtrl = TextEditingController(text: _node?.url ?? '');
    _ownKey = _node?.hasOwnKey ?? false;
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

    if (node == null) {
      final added = await cubit.addVoiceRegion(label: label, url: url);
      if (!added.success) return added;
      // The row it just made, found by the label that made it: labels are
      // unique per server, and the add has already re-read the server, so
      // this is the node and not a guess. A key is a second write to a second
      // table — if it fails, the region is there on the server's pair and the
      // message says so, which is a state the edit dialog can finish.
      final made = cubit.state.selectedServer?.livekitNodes
          .where((n) => n.label == label)
          .firstOrNull;
      if (made == null) return added;
      return _writeCredentials(cubit, made);
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
  /// Three outcomes and one of them is silence: typing nothing into the two
  /// fields of a region that already has a key means "leave it alone", since
  /// the fields cannot show what is stored and so cannot be a true copy of
  /// it. Turning the box off is the only way to take a key back.
  Future<({bool success, String? error})> _writeCredentials(
    ServerCubit cubit,
    LiveKitNode node,
  ) async {
    if (node.isDefault) return (success: true, error: null);

    if (!_ownKey) {
      if (!node.hasOwnKey) return (success: true, error: null);
      return cubit.setVoiceRegionCredentials(nodeId: node.id);
    }

    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();
    if (apiKey.isEmpty && secret.isEmpty) {
      return node.hasOwnKey
          ? (success: true, error: null)
          : (
              success: false,
              error:
                  'Type this region\'s API key and secret, or untick the box '
                  'to use the server\'s.',
            );
    }
    if (apiKey.isEmpty || secret.isEmpty) {
      return (
        success: false,
        error: 'A region needs both an API key and a secret, or neither.',
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
            CheckboxRow(
              label: 'This region has its own LiveKit key',
              value: _ownKey,
              onChanged: _isLoading
                  ? (_) {}
                  : (v) => setState(() {
                      _ownKey = v;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 6),
            Text(
              _ownKey
                  ? 'Its key never leaves this box, so whoever runs it cannot '
                        'mint tokens for calls in your other regions. Set the '
                        'same pair in its livekit.yaml.'
                  : 'It signs with the server\'s own key, the same one the '
                        'first region uses. Simpler to set up, and a break-in '
                        'on this box reaches every region.',
              style: AppText.label.copyWith(color: theme.textTertiary),
            ),
            if (_ownKey) ...[
              const SizedBox(height: 14),
              AppTextField(
                controller: _apiKeyCtrl,
                label: 'LiveKit API key',
                hint: _node?.hasOwnKey == true
                    ? 'Leave blank to keep current'
                    : 'APIxxxxxxxx',
                enabled: !_isLoading,
                obscureText: true,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _secretCtrl,
                label: 'LiveKit secret key',
                hint: _node?.hasOwnKey == true
                    ? 'Leave blank to keep current'
                    : 'The secret from its livekit.yaml',
                enabled: !_isLoading,
                obscureText: true,
                onChanged: (_) => setState(() => _error = null),
              ),
            ],
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
Future<void> showVoiceRegionDialog(
  BuildContext context, {
  LiveKitNode? node,
}) {
  final cubit = context.read<ServerCubit>();
  return showCustomDialog(
    context: context,
    build: (_) => BlocProvider.value(
      value: cubit,
      child: VoiceRegionDialog(node: node),
    ),
  );
}
