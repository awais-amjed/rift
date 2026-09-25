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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  /// Sends only what was actually changed, so renaming a region doesn't
  /// rewrite its address with the same string and wake every client that
  /// watches the node for one.
  Future<({bool success, String? error})> _write(ServerCubit cubit) async {
    final label = _nameCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    final node = _node;
    if (node == null) return cubit.addVoiceRegion(label: label, url: url);

    if (label != node.label) {
      final renamed = await cubit.updateVoiceRegion(
        nodeId: node.id,
        label: label,
      );
      if (!renamed.success) return renamed;
    }
    if (url == node.url) return (success: true, error: null);

    // The address, by whichever route owns it — the default's lives on the
    // server row, every other region's on its own.
    return node.isDefault
        ? cubit.updateDefaultVoiceRegion(url: url)
        : cubit.updateVoiceRegion(nodeId: node.id, url: url);
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
                : 'Give it the same API key and secret as the server\'s own '
                      'LiveKit — every region signs with the one pair.',
            style: AppText.label.copyWith(color: theme.textTertiary),
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
