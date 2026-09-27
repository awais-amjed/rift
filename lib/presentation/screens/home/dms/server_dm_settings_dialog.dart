import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_limits.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/services/limit_input.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/limit_field.dart';

/// How much history this server's DMs keep.
///
/// The sibling of `ChannelSettingsDialog`, and deliberately shaped like it: the
/// same two boxes, the same three-valued rule, the same helper line spelling out
/// what blank inherits. A channel's overrides hang off that channel; DMs have no
/// single row to hang off, so theirs live on `servers` and are reached by
/// right-clicking the Server DMs entry.
///
/// There is nothing here about *one* conversation, and there won't be. A DM
/// belongs to two people, so neither of them is the right person to decide how
/// long the other's messages survive — and the setting exists to protect the
/// operator's disk, which makes it the operator's call.
class ServerDmSettingsDialog extends StatefulWidget {
  const ServerDmSettingsDialog({super.key});

  @override
  State<ServerDmSettingsDialog> createState() => _ServerDmSettingsDialogState();
}

class _ServerDmSettingsDialogState extends State<ServerDmSettingsDialog> {
  late final ServerLimits _initial =
      context.read<ServerCubit>().state.selectedServer?.limits ??
      ServerLimits.defaults;

  /// Blank when DMs inherit — including when they inherit a server that keeps
  /// everything, because "inherit" is about where the number comes from, not
  /// what it is.
  late final TextEditingController _retentionCtrl = TextEditingController(
    text: _initial.dmRetentionDays?.toString() ?? '',
  );
  late final TextEditingController _capCtrl = TextEditingController(
    text: _initial.dmHistoryCap?.toString() ?? '',
  );

  bool _isLoading = false;
  String? _error;

  int? get _retention => LimitInput.parse(_retentionCtrl.text);
  int? get _cap => LimitInput.parse(_capCtrl.text);

  bool get _changed =>
      _retention != _initial.dmRetentionDays || _cap != _initial.dmHistoryCap;

  bool get _canSubmit =>
      _retention != LimitInput.invalid &&
      _cap != LimitInput.invalid &&
      _changed;

  /// What DMs fall back to, spelled out — an admin shouldn't have to open the
  /// server dialog to find out what "inherit" currently means.
  String _inheritHelper(int serverValue, String unit, String whenOff) {
    final fallback = serverValue == ServerLimits.unlimited
        ? whenOff
        : '$serverValue $unit';
    return 'Blank inherits the server setting ($fallback). 0 means no limit '
        'on DMs.';
  }

  @override
  void dispose() {
    _retentionCtrl.dispose();
    _capCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Everything else carried through unchanged: `ServerLimits` travels whole,
    // so building a fresh one from the typed boxes would send the defaults for
    // the rest and quietly reset them. Every field is named for that reason —
    // this once left out the call, member and storage limits, and saving DM
    // settings put all three back to unlimited.
    final result = await context.read<ServerCubit>().updateServerDetails(
      limits: ServerLimits(
        maxAttachmentBytes: _initial.maxAttachmentBytes,
        messageRetentionDays: _initial.messageRetentionDays,
        messageHistoryCap: _initial.messageHistoryCap,
        dmRetentionDays: _retention,
        dmHistoryCap: _cap,
        maxVoiceParticipants: _initial.maxVoiceParticipants,
        maxShareMbps: _initial.maxShareMbps,
        maxMembers: _initial.maxMembers,
        maxStorageBytes: _initial.maxStorageBytes,
        dmOpeningsPerHour: _initial.dmOpeningsPerHour,
      ),
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isLoading = false;
        _error = result.error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Server DM settings',
      subtitle: 'Applies to every conversation on this server',
      error: _error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LimitField(
            controller: _retentionCtrl,
            label: 'Delete messages older than',
            unit: 'days',
            hint: 'Server setting',
            helper: _inheritHelper(
              _initial.messageRetentionDays,
              'days',
              'keep forever',
            ),
            enabled: !_isLoading,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          LimitField(
            controller: _capCtrl,
            label: 'Keep at most',
            unit: 'messages',
            hint: 'Server setting',
            // Said out loud because it is the one rule people get wrong: the
            // cap is the conversation's, not each person's.
            helper:
                '${_inheritHelper(_initial.messageHistoryCap, 'messages', 'keep everything')} '
                'Counts both people together.',
            enabled: !_isLoading,
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
          label: _isLoading ? 'Saving...' : 'Save',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
    );
  }
}
