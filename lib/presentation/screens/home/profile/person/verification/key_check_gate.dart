import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../common/chat/composer_notice.dart';

/// The composer, or — while somebody you verified has a key you have not
/// checked — a notice in its place that offers the check.
///
/// Only for the verified: for everybody else a change is the amber chip and
/// a line in the conversation, and the composer stays. Verifying is saying
/// "this key is theirs", so a new one is held until you look, as Signal does.
/// "Forget" in the code sheet is the way to send anyway.
class KeyCheckGate extends StatelessWidget {
  /// `<tier>:<their id>`, or null while no conversation is open.
  final String? person;
  final String name;
  final VoidCallback onCheck;
  final Widget child;

  const KeyCheckGate({
    super.key,
    required this.person,
    required this.name,
    required this.onCheck,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final person = this.person;
    final held = context.select<AppCubit, bool>(
      (c) => person != null && c.state.keyChangedSinceVerified(person),
    );
    if (!held) return child;
    return ComposerNotice(
      icon: Icons.key_rounded,
      text:
          "$name's safety key changed since you verified them. Compare "
          'codes before you send anything.',
      actionLabel: 'Compare codes',
      onAction: onCheck,
    );
  }
}
