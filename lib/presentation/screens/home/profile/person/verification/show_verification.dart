import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/app_sheet.dart';
import '../../../../../responsive/shell_scope.dart';
import 'safety_code_dialog.dart';

/// Everything that opens a safety code, so the profile, a DM header and a
/// call all reach the same screen by the same route.
///
/// The code needs this device's own chat key, which comes from the vault and
/// therefore arrives a frame late. Every entry point here is async for that
/// reason and for no other.

/// The code for one person, or null when either side has no key to compare —
/// somebody who has never opened the app, or a vault that is still locked.
Future<String?> safetyCodeFor(
  BuildContext context, {
  required String theirId,
  required String? theirChatKey,
  required String myId,
  required String host,
}) async {
  if (theirChatKey == null || myId.isEmpty) return null;
  final identity = await context.read<VaultCubit>().getChatIdentityForHost(
    host,
  );
  return SafetyCode.between(
    myKey: identity.publicKeyBase64,
    myId: myId,
    theirKey: theirChatKey,
    theirId: theirId,
  );
}

/// Show [code] for [personName], as a sheet on a phone and a dialog
/// elsewhere.
///
/// [person] is `<tier>:<their id>` — see [AppState.verifiedCodes].
void showSafetyCode(
  BuildContext context, {
  required String personName,
  required String person,
  required String code,
}) {
  // Built here, with the cubit read here: both routes rebuild for reasons
  // that have nothing to do with what opened them.
  final dialog = BlocProvider.value(
    value: context.read<AppCubit>(),
    child: SafetyCodeDialog(personName: personName, person: person, code: code),
  );
  if (context.layoutMode.isCompact) {
    showAppSheet<void>(context, dialog);
    return;
  }
  showCustomDialog<void>(context: context, build: (_) => dialog);
}

/// Compute and show in one step, for a surface that knows exactly whose key
/// it is claiming to have sealed to — a DM header, a person in a call.
Future<void> showSafetyCodeFor(
  BuildContext context, {
  required String personName,
  required String tier,
  required String theirId,
  required String? theirChatKey,
  required String myId,
  required String host,
}) async {
  final code = await safetyCodeFor(
    context,
    theirId: theirId,
    theirChatKey: theirChatKey,
    myId: myId,
    host: host,
  );
  if (!context.mounted) return;
  // Never a press that does nothing: a key this client has not been given is
  // the one case, and saying so beats a chip that looks broken.
  if (code == null) {
    HelperMethods.showToast(
      title: 'Nothing to compare yet',
      description:
          '$personName has not published a key this device can see. Their '
          'safety code appears once they have.',
    );
    return;
  }
  showSafetyCode(
    context,
    personName: personName,
    person: '$tier:$theirId',
    code: code,
  );
}
