/// What to tell somebody whose call the server refused or could not answer,
/// by the code it raised (`start_dm_call`, `answer_dm_call`).
///
/// Pure, like [DmRefusal], and for the same reason: `call_not_accepted` covers
/// a block and must read like a setting, never like being blocked.
class CallRefusal {
  const CallRefusal._();

  /// A sentence for [code], or null when it is not a refusal this knows.
  static String? describe(String? code, {required String peerName}) =>
      switch (code) {
        'call_needs_conversation' =>
          'You can call $peerName once you\'ve talked. Send them a message '
              'first, and if it goes as a request, wait for them to accept '
              'it.',
        'call_not_accepted' =>
          '$peerName isn\'t taking calls from you right now.',
        'call_rate_limited' =>
          'You\'ve called $peerName a lot without an answer. Try again later.',
        'timed_out' => 'You\'re timed out, so you can\'t start calls yet.',
        'cannot_connect' =>
          'You don\'t have permission to join calls on this server.',
        'user_not_found' => '$peerName isn\'t on this server anymore.',
        'call_not_ringing' => 'This call was answered on another device.',
        'call_ended' || 'call_not_found' => 'That call has already ended.',
        _ => null,
      };
}
