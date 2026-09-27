/// What to tell somebody whose DM the server refused, by the code it raised.
///
/// Pure, and apart from the cubit, because the wording is the part with rules:
/// a block and a "no one new" setting must read the same, since the server
/// raises the same code for both on purpose — a sender told they were blocked
/// is a sender invited to make a second account.
class DmRefusal {
  const DmRefusal._();

  /// A sentence for [code], or null when it is not a refusal this knows.
  static String? describe(String? code, {required String peerName}) =>
      switch (code) {
        'dm_request_pending' =>
          'Your message request to $peerName is waiting. You can send more '
              'once they accept it.',
        'dm_not_accepted' =>
          '$peerName isn\'t accepting messages from you right now.',
        'dm_rate_limited' =>
          'You\'ve started a lot of new conversations in the last hour. '
              'Try again later.',
        'timed_out' => 'You\'re timed out, so you can\'t send messages yet.',
        _ => null,
      };
}
