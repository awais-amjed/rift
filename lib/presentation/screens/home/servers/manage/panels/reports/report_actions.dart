import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../../data/classes/api_response.dart';
import '../../../../../../../data/classes/user_permissions.dart';
import '../../../../../../../data/enums/server_permission.dart';
import '../../../../../../../logic/cubits/reports/reports_cubit.dart';
import '../../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../../logic/helper_methods.dart';
import '../../../../../../common/app_button.dart';
import '../../../../../../common/confirm_dialog.dart';
import '../../../../reports/time_out_picker.dart';

/// What a reviewer can do about an open report — only what they hold the
/// permission for, and only what applies: no deletion for a report about a
/// person, no time-out or ban for a webhook, no ban for somebody already
/// banned.
///
/// Each action is done, then recorded (`ReportsCubit`); the server checks the
/// record against what happened, so a refusal on the way is said plainly.
class ReportActions extends StatefulWidget {
  final ReportEntry entry;

  const ReportActions({super.key, required this.entry});

  @override
  State<ReportActions> createState() => _ReportActionsState();
}

class _ReportActionsState extends State<ReportActions> {
  bool _busy = false;

  String get _about =>
      widget.entry.report.target?.displayName ??
      widget.entry.report.message?.originName ??
      'them';

  static String _describe(APIResponse response) => switch (response.errorCode) {
    'outcome_not_done' =>
      'That didn\'t go through, so the report is still open. The message '
          'may be in a channel you can\'t moderate.',
    'already_resolved' => 'Someone else closed this report already.',
    'cannot_moderate_peer' ||
    'cannot_moderate_admin' => 'You can\'t do that to this person.',
    _ => response.error ?? 'Something went wrong.',
  };

  Future<void> _run(Future<APIResponse> Function() action) async {
    setState(() => _busy = true);
    final response = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!response.success) HelperMethods.showError(error: _describe(response));
  }

  Future<void> _delete(ReportsCubit cubit) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete this message?',
      message:
          'It is removed for everyone, with its attachments. The report '
          'keeps its copy.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (confirmed) await _run(() => cubit.deleteMessage(widget.entry));
  }

  Future<void> _timeOut(ReportsCubit cubit) async {
    final length = await showTimeOutPicker(context, _about);
    if (length != null) {
      await _run(() => cubit.timeOut(widget.entry, length.duration));
    }
  }

  Future<void> _ban(ReportsCubit cubit) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Ban $_about?',
      message:
          'They lose access to this server now. Every open report about '
          'them closes with this one.',
      confirmLabel: 'Ban',
      icon: Icons.gavel_rounded,
      isDestructive: true,
    );
    if (confirmed) await _run(() => cubit.ban(widget.entry));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReportsCubit>();
    final perms = context.select<ServerCubit, UserPermissions?>(
      (c) => c.state.myPermissions,
    );
    bool can(ServerPermission p) => perms?.can(p) ?? false;
    final report = widget.entry.report;
    final target = report.target;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Not in a channel the reviewer cannot see: the delete would reach
        // nothing, and the report would stay open saying so.
        if (report.message != null &&
            report.channelName != null &&
            can(ServerPermission.manageMessages))
          AppButton(
            label: 'Delete message',
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => unawaited(_delete(cubit)),
          ),
        if (target != null &&
            !target.isBanned &&
            can(ServerPermission.muteMembers))
          AppButton(
            label: 'Time out',
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => unawaited(_timeOut(cubit)),
          ),
        if (target != null &&
            !target.isBanned &&
            can(ServerPermission.banMembers))
          AppButton(
            label: 'Ban',
            variant: AppButtonVariant.secondary,
            onPressed: _busy ? null : () => unawaited(_ban(cubit)),
          ),
        AppButton(
          label: 'Dismiss',
          variant: AppButtonVariant.secondary,
          isLoading: _busy,
          onPressed: _busy
              ? null
              : () => unawaited(_run(() => cubit.dismiss(widget.entry))),
        ),
      ],
    );
  }
}
