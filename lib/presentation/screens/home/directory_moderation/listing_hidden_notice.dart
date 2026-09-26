import 'package:flutter/material.dart';

import '../../../common/message_banner.dart';

/// Told to a listing's owner when a Rift moderator has hidden it.
///
/// Its owner is the only person besides a moderator who can still see the
/// listing, so this is the one place they find out it left the directory —
/// and why, in the moderator's words.
class ListingHiddenNotice extends StatelessWidget {
  final String? reason;

  const ListingHiddenNotice({super.key, this.reason});

  @override
  Widget build(BuildContext context) {
    final why = reason?.trim() ?? '';
    return MessageBanner(
      kind: MessageBannerKind.caution,
      message:
          'Rift moderators hid this listing from the directory'
          '${why.isEmpty ? '.' : ': $why'} Editing it does not bring it back.',
    );
  }
}
