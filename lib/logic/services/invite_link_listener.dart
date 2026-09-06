import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../../data/invite_link.dart';

/// Invites arriving from outside the app — a tapped link, or a click handed
/// over by the web landing page.
///
/// One place rather than a listener per platform: `app_links` already flattens
/// Android intents, macOS URL events and the desktop schemes into one stream,
/// and what is left to decide is the same everywhere — is this an invite, and
/// has it been dealt with already.
///
/// A link that arrives before anything is listening is not lost. Opening the
/// app *is* how a cold-start link is delivered, so the first one is held and
/// handed to the first listener; that is [_pending].
class InviteLinkListener {
  InviteLinkListener._();

  static final InviteLinkListener instance = InviteLinkListener._();

  final AppLinks _appLinks = AppLinks();

  // Lives as long as the process: this is the one listener for links
  // arriving from outside, and there is no moment to stop wanting them.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _subscription;

  /// An invite that arrived with no one to receive it — a cold start.
  InviteLink? _pending;

  void Function(InviteLink)? _onInvite;

  /// Whether the launch link has been asked for. Once per process — it does
  /// not change, and handling it twice would open the join dialog twice.
  bool _initialConsumed = false;

  /// A link just handled, briefly, so a duplicate delivery is not acted on.
  String? _echo;

  /// Starts listening, and replays a cold-start invite to [onInvite].
  ///
  /// Safe to call more than once: the later caller takes over, which is what
  /// makes this survive a hot restart in development.
  Future<void> start(void Function(InviteLink) onInvite) async {
    _onInvite = onInvite;

    final pending = _pending;
    if (pending != null) {
      _pending = null;
      onInvite(pending);
    }

    if (_subscription == null) {
      try {
        // The *string* stream, not the Uri one. An invite carries its payload
        // in the fragment (`rift://join#<server-url>#<code>`), and a second
        // `#` inside a fragment is not legal — so `Uri.toString()` re-encodes
        // it to `%23` and the two halves come back glued together. The
        // platform hands over the text exactly as it arrived; that is what to
        // read.
        _subscription = _appLinks.stringLinkStream.listen(
          _handle,
          onError: (Object e) => debugPrint('InviteLinkListener: stream – $e'),
        );
      } catch (e) {
        // A platform with no link plumbing is not a reason to fail startup —
        // pasting an invite still works everywhere.
        debugPrint('InviteLinkListener: could not listen – $e');
      }
    }

    // The link that launched the app has to be *asked* for; it will not come
    // down the stream.
    //
    // `AppLinks` is a singleton with one broadcast controller behind one
    // platform channel, and supabase_flutter — which uses the same package to
    // catch OAuth callbacks — subscribes during `Supabase.initialize`, long
    // before this does. The native side replays the launch link to the first
    // listener only, and a broadcast stream has nothing to replay to the
    // second. So an invite that started the app went to a listener looking for
    // an auth callback and was dropped, in complete silence.
    if (_initialConsumed) return;
    _initialConsumed = true;
    try {
      final initial = await _appLinks.getInitialLinkString();
      if (initial == null) return;
      _handle(initial);
      // Belt and braces: if the ordering above ever changes and the stream
      // does deliver it, the same invite must not open two dialogs. A repeat
      // this soon is an echo; the same link tapped again later is not.
      _echo = initial;
      Timer(const Duration(seconds: 3), () => _echo = null);
    } catch (e) {
      debugPrint('InviteLinkListener: could not read the launch link – $e');
    }
  }

  /// Stops delivering to the current receiver, holding anything that arrives
  /// until another one appears.
  void detach() => _onInvite = null;

  void _handle(String link) {
    if (_echo == link) {
      _echo = null;
      return;
    }
    final invite = InviteLink.parse(link);
    if (invite == null) {
      debugPrint('InviteLinkListener: not an invite – $link');
      return;
    }
    final receiver = _onInvite;
    if (receiver == null) {
      _pending = invite;
      return;
    }
    receiver(invite);
  }
}
