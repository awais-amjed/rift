import 'package:flutter/gestures.dart';

import '../../../../logic/services/open_link.dart';

/// The tap handlers behind a message's links, owned by the row.
///
/// A `TextSpan` can carry a recognizer but cannot dispose one, so whoever
/// builds the span has to. The row calls [reset] at the top of each build
/// and hands [forUrl] to the span builder; whatever the last build made is
/// released the next time round, and everything on [dispose].
class LinkTapRecognizers {
  final List<TapGestureRecognizer> _live = [];

  TapGestureRecognizer forUrl(String url) {
    final recognizer = TapGestureRecognizer()..onTap = () => _open(url);
    _live.add(recognizer);
    return recognizer;
  }

  void reset() {
    for (final r in _live) {
      r.dispose();
    }
    _live.clear();
  }

  void dispose() => reset();

  static Future<void> _open(String url) async {
    await openExternalLink(url);
  }
}
