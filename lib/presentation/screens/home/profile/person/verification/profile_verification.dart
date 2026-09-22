import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/app_sheet.dart';
import '../../../../../responsive/shell_scope.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';
import '../widgets/profile_section.dart';
import 'safety_code_dialog.dart';

/// Whether this person's key has been checked, and the way to check it.
///
/// A profile says "Encrypted chat: Ready" — which only means they published
/// a key, not that it is theirs. This is the part that can answer that, and
/// it is deliberately the person's own answer rather than the app's: the two
/// devices show the same sixty digits and somebody compares them.
class ProfileVerification extends StatefulWidget {
  /// Their id on this tier, and the key their messages are sealed to.
  final String personId;
  final String personName;
  final String? theirChatKey;

  /// My own id on the same tier, and the host my chat key belongs to — the
  /// server's for a member, central's for an account.
  final String myId;
  final String host;

  /// `server` or `central`, which is what keeps the two tiers' answers apart
  /// for somebody who is both.
  final String tier;

  const ProfileVerification({
    super.key,
    required this.personId,
    required this.personName,
    required this.theirChatKey,
    required this.myId,
    required this.host,
    required this.tier,
  });

  @override
  State<ProfileVerification> createState() => _ProfileVerificationState();
}

class _ProfileVerificationState extends State<ProfileVerification> {
  String? _code;

  String get _person => '${widget.tier}:${widget.personId}';

  @override
  void initState() {
    super.initState();
    _compute();
  }

  /// My half needs the vault, so the code arrives a frame or two late. Until
  /// it does the section says nothing rather than offering a button that
  /// would open an empty dialog.
  Future<void> _compute() async {
    final theirKey = widget.theirChatKey;
    if (theirKey == null) return;
    final identity = await context.read<VaultCubit>().getChatIdentityForHost(
      widget.host,
    );
    if (!mounted) return;
    setState(() {
      _code = SafetyCode.between(
        myKey: identity.publicKeyBase64,
        myId: widget.myId,
        theirKey: theirKey,
        theirId: widget.personId,
      );
    });
  }

  void _open(String code) {
    // Built here, with the cubit read here: the sheet and the dialog are both
    // routes, and this widget's context is the one that still has an AppCubit
    // above it.
    final dialog = BlocProvider.value(
      value: context.read<AppCubit>(),
      child: SafetyCodeDialog(
        personName: widget.personName,
        person: _person,
        code: code,
      ),
    );
    // A sheet over the profile's own sheet on a phone. As a dialog it drew
    // its contents straight onto the profile behind it, with no surface of
    // its own — `sheetOnPhone` styles the modal for a sheet and expects to be
    // opened as one.
    if (context.layoutMode.isCompact) {
      showAppSheet<void>(context, dialog);
      return;
    }
    showCustomDialog<void>(context: context, builder: (_) => dialog);
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    if (code == null) return const SizedBox.shrink();

    final theme = context.theme;
    final verified = context.select<AppCubit, String?>(
      (c) => c.state.verifiedCodes[_person],
    );
    final changed = verified != null && verified != code;
    final (icon, colour, line) = switch ((verified, changed)) {
      (null, _) => (
        Icons.shield_outlined,
        theme.textTertiary,
        'Not verified yet — compare your safety code to be sure this key is '
            'theirs.',
      ),
      (_, true) => (
        Icons.error_outline_rounded,
        CustomColors.error,
        'Their key changed after you verified them. Check the new code.',
      ),
      _ => (
        Icons.verified_user_rounded,
        CustomColors.success,
        'Verified on this device — the code matched when you checked it.',
      ),
    };

    return ProfileSection(
      label: 'Verification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: colour),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line,
                  style: AppText.secondary.copyWith(color: theme.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppButton(
            label: changed
                ? 'Check the new code'
                : verified != null
                ? 'Safety code'
                : 'Verify',
            variant: AppButtonVariant.secondary,
            expanded: true,
            icon: const Icon(Icons.qr_code_2_rounded, size: 15),
            onPressed: () => _open(code),
          ),
        ],
      ),
    );
  }
}
