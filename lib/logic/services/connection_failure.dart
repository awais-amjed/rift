import 'dart:io';

import 'package:livekit_client/livekit_client.dart' as lk;

/// Over the helper budget and one job: turning a failed join into a sentence.
/// Each case is a few lines and there are many cases.
///
/// A failed voice join, described for the person who hit it rather than for a
/// log line.
///
/// LiveKit surfaces the raw HTTP body of its validate endpoint as the exception
/// message, so the untranslated text is things like "requested room does not
/// exist" — accurate, and meaningless unless you know how Rift provisions
/// rooms. Each case below says what actually went wrong and whether trying
/// again can fix it, and keeps the original text in [detail] so a bug report is
/// still worth something.
class ConnectionFailure {
  /// Short statement of what failed. Reads as a headline, no trailing period.
  final String title;

  /// One or two sentences: what it means, and what to do about it.
  final String message;

  /// The original error text, shown small and quiet under the message.
  final String? detail;

  /// Whether another attempt could plausibly succeed. A misconfigured server
  /// will fail the same way forever, and offering a button that can't work is
  /// worse than offering none.
  final bool canRetry;

  const ConnectionFailure({
    required this.title,
    required this.message,
    this.detail,
    this.canRetry = true,
  });

  /// The connection failed but nothing recorded why. Should not happen; if it
  /// does, retrying is the only sensible offer.
  const ConnectionFailure.unknown()
    : title = 'Could not join the channel',
      message = 'The connection failed without saying why.',
      detail = null,
      canRetry = true;

  /// No server is selected — a UI state, not a connection problem.
  const ConnectionFailure.noServer()
    : title = 'No server selected',
      message = 'Pick a server before joining a voice channel.',
      detail = null,
      canRetry = false;

  /// The server record carries no LiveKit URL, so there is nothing to dial.
  const ConnectionFailure.noLiveKitUrl()
    : title = 'Voice not configured',
      message =
          'This server has no LiveKit URL set, so it cannot host voice '
          'channels. That has to be fixed on the server.',
      detail = null,
      canRetry = false;

  /// The edge function that mints channel tokens refused or failed.
  ///
  /// Retryable on purpose: this call is also what creates the LiveKit room, so
  /// a transient failure here is exactly the kind another attempt clears.
  const ConnectionFailure.tokenRequest(String? error)
    : title = 'Could not get access to this channel',
      message =
          'The server would not let this device into the channel. You may '
          'have lost access to it, or the server may be having trouble.',
      detail = error,
      canRetry = true;

  /// The call already holds as many people as the operator allows
  /// (`max_voice_participants`, self-host 028).
  ///
  /// Its own case rather than [tokenRequest]'s, because that one reads "you
  /// may have lost access, or the server may be having trouble" — and neither
  /// is true here. Nothing is broken and nothing has been taken away; the
  /// room is simply full, which is a thing the person can wait out.
  const ConnectionFailure.callFull(String? error)
    : title = 'This call is full',
      message =
          'The server sets how many people one call may hold. Someone has to '
          'leave before anybody else can join.',
      detail = error,
      canRetry = true;

  /// No channel key, so there is nothing to encrypt the call with.
  ///
  /// Retryable, and the retry usually works: the common cause is a member who
  /// has just joined the server and whom nobody has sealed this channel's key
  /// to yet. Another member's client heals that within seconds.
  ///
  /// The call is refused rather than joined unencrypted, which would work and
  /// sound completely normal. A room you cannot join is a bug somebody reports;
  /// a room that is quietly readable by the server is the promise breaking with
  /// nobody noticing.
  const ConnectionFailure.noChannelKey()
    : title = 'Waiting for this channel’s key',
      message =
          'Calls here are end-to-end encrypted, and this device does not have '
          'the key yet. Another member’s app hands it over automatically — '
          'this usually clears in a few seconds.',
      detail = null,
      canRetry = true;

  /// Translates whatever `room.connect` threw.
  factory ConnectionFailure.from(Object error) {
    final detail = _detailOf(error);

    if (error is lk.ConnectException) return _fromConnect(error, detail);
    if (error is lk.MediaConnectException) {
      return ConnectionFailure(
        title: 'Voice could not get through',
        message:
            'The server accepted the connection but no audio or video could '
            'reach it. A firewall or router is most likely blocking the media '
            'ports.',
        detail: detail,
      );
    }
    if (error is lk.TrackCreateException) {
      return ConnectionFailure(
        title: 'Microphone or camera unavailable',
        message:
            'Your device would not hand over the microphone or camera. Check '
            'that nothing else is using it and that Rift has permission.',
        detail: detail,
      );
    }
    if (error is lk.TimeoutException) {
      return ConnectionFailure(
        title: 'The voice server did not respond',
        message:
            'It took too long to answer. It may be overloaded or only just '
            'starting up.',
        detail: detail,
      );
    }
    if (error is SocketException || error is HttpException) {
      return _unreachable(detail);
    }

    return ConnectionFailure(
      title: 'Could not join the channel',
      message: 'Something went wrong while connecting.',
      detail: detail,
    );
  }

  static ConnectionFailure _fromConnect(lk.ConnectException e, String? detail) {
    final body = e.message.toLowerCase();

    // Checked before the status code: LiveKit reports this as a 404, which
    // `reason` then generalises to NotAllowed along with every real permission
    // failure.
    if (e.statusCode == 404 || body.contains('does not exist')) {
      // Says nothing about rooms or tokens: the person reading this wanted to
      // join a call, and cannot act on either. The raw error still travels in
      // [detail], which is where anybody debugging it will look.
      return ConnectionFailure(
        title: 'This call needs reopening',
        message:
            'Nobody has been in here for a while, so the call closed itself. '
            'Trying again opens it back up.',
        detail: detail,
      );
    }

    if (e.statusCode == 401 || e.statusCode == 403) {
      return ConnectionFailure(
        title: 'Could not get into this call',
        message:
            'Your access may have changed, or too long has passed since you '
            'last joined. Trying again asks for fresh permission.',
        detail: detail,
      );
    }

    // 503 with no socket at all is how the SDK reports "no route out".
    if (e.statusCode == 503 || body.contains('no internet connection')) {
      return _unreachable(detail);
    }

    if (e.reason == lk.ConnectionErrorReason.Timeout ||
        body.contains('timed out')) {
      return ConnectionFailure(
        title: 'The voice server did not respond',
        message:
            'It took too long to answer. It may be overloaded or only just '
            'starting up.',
        detail: detail,
      );
    }

    // Status 0 means the socket never opened — the server did not answer at
    // all, rather than answering with a refusal.
    if (e.statusCode == 0) return _unreachable(detail);

    return ConnectionFailure(
      title: 'The voice server rejected the connection',
      message: 'It answered, but would not let this device in.',
      detail: detail,
    );
  }

  static ConnectionFailure _unreachable(String? detail) => ConnectionFailure(
    title: 'Cannot reach this server\'s voice service',
    message:
        'Nothing answered at the address this server uses for calls. It is '
        'probably offline — otherwise check your own connection, or that the '
        'address is still correct.',
    detail: detail,
  );

  /// LiveKit's own `toString` prefixes the class name, which is noise next to a
  /// message written for a person.
  static String? _detailOf(Object error) {
    if (error is lk.LiveKitException) return error.message;
    return error.toString();
  }
}
