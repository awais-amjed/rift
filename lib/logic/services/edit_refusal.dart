import 'dm_refusal.dart';

/// What to tell somebody whose edit the server refused.
///
/// An edit is a row update, so a refusal arrives as Postgres' 42501 rather
/// than a raised code — and once the row is your own there are exactly two
/// causes left: a time-out, or, in a DM, a recipient who will not take it.
class EditRefusal {
  const EditRefusal._();

  /// A sentence for [code], or null when it is not a refusal this knows.
  ///
  /// Pass [peerName] for a DM, where the second cause reads exactly as a
  /// refused message does ([DmRefusal]) — a block must never say it is one. A
  /// channel has only the first.
  static String? describe(
    String? code, {
    required bool timedOut,
    String? peerName,
  }) {
    if (code != '42501') return null;
    if (timedOut || peerName == null) {
      return 'You\'re timed out, so you can\'t edit messages yet.';
    }
    return DmRefusal.describe('dm_not_accepted', peerName: peerName);
  }
}
