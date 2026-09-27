import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../reports/show_report_dialog.dart';

/// Over the open conversation when it is a request: somebody new asked to
/// message us, and this is where we answer.
///
/// The composer stays under it, because replying is an answer too — it
/// accepts. The four buttons are for everyone who would rather not type.
/// Ignoring tells nobody, and neither does blocking.
class DmRequestBanner extends StatelessWidget {
  final String peerId;
  final String peerName;

  /// Already put away once. Still answerable: ignoring is not refusing.
  final bool ignored;

  const DmRequestBanner({
    super.key,
    required this.peerId,
    required this.peerName,
    this.ignored = false,
  });

  Future<void> _answer(BuildContext context, {required bool accept}) async {
    final cubit = context.read<DmCubit>();
    final response = await cubit.answerRequest(peerId, accept: accept);
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'Something went wrong');
      return;
    }
    if (!accept) cubit.closeConversation();
  }

  Future<void> _block(BuildContext context) async {
    final cubit = context.read<DmCubit>();
    final response = await cubit.setBlocked(peerId, blocked: true);
    if (!response.success) {
      HelperMethods.showError(error: response.error ?? 'Could not block');
      return;
    }
    cubit.closeConversation();
    HelperMethods.showToast(
      title: 'Blocked',
      description: '$peerName can no longer message you here.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: themeState.bgTertiary,
          borderRadius: BorderRadius.circular(K.radiusCard),
          border: Border.all(color: themeState.borderElevated),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 10,
          children: [
            Text(
              ignored
                  ? 'You ignored $peerName\'s message request. They weren\'t '
                        'told.'
                  : '$peerName wants to message you.',
              style: AppText.row.copyWith(color: themeState.textPrimary),
            ),
            Text(
              'They can\'t send more until you accept. Replying accepts too.',
              style: AppText.meta.copyWith(color: themeState.textTertiary),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppButton(
                  label: 'Accept',
                  onPressed: () => unawaited(_answer(context, accept: true)),
                ),
                if (!ignored)
                  AppButton(
                    label: 'Ignore',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => unawaited(_answer(context, accept: false)),
                  ),
                AppButton(
                  label: 'Block',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => unawaited(_block(context)),
                ),
                AppButton(
                  label: 'Report',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => unawaited(
                    showReportMemberDialog(
                      context,
                      userId: peerId,
                      displayName: peerName,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
