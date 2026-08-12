import 'package:flutter/material.dart';

import '../../../../../common/hint_card.dart';

/// What the publish dialog shows to a privacy-mode user.
///
/// Publishing needs a central account because the listing is *owned* by one —
/// that is what lets you edit or withdraw it later, and from another device.
/// Nothing else about the feature requires central, and the server itself
/// works exactly as before without it.
class NoCentralAccount extends StatelessWidget {
  const NoCentralAccount({super.key});

  @override
  Widget build(BuildContext context) {
    return const HintCard(
      icon: Icons.cloud_off_outlined,
      text:
          'The directory lives on the Rift central server, so listing a server '
          'needs a Rift account — that is what makes the listing yours to edit '
          'or remove later, from any device. Sign in under Settings → Account. '
          'Nothing about this server leaves the device until you do.',
    );
  }
}
