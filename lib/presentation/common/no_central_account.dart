import 'package:flutter/material.dart';

import 'hint_card.dart';

/// What the directory shows to a privacy-mode user.
///
/// The server directory is the one part of Rift that has to live on central —
/// it is the only place two strangers already share — so both ends of it need
/// an account. Nothing else about a server does, and one without a listing
/// works exactly as before, reachable by invite link.
class NoCentralAccount extends StatelessWidget {
  /// Why *this* screen needs an account. The rest of the card — what to do
  /// about it, and what doesn't happen until you do — is the same wherever it
  /// appears.
  final String need;

  const NoCentralAccount({super.key, required this.need});

  @override
  Widget build(BuildContext context) {
    return HintCard(
      icon: Icons.cloud_off_outlined,
      text:
          '$need Sign in under Settings → Account & backup. Nothing about '
          'this device or its servers reaches the Rift central server until '
          'you do.',
    );
  }
}
