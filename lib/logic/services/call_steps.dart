import 'serial_queue.dart';

/// Joining and leaving a call, one at a time, the latest press winning.
///
/// A join waits on the network twice, for the token and key and then for the
/// room, and a leave or another join pressed meanwhile used to run beside it.
/// Neither saw the other. A leave found no room to close, and the join then
/// connected anyway, into a call with no Leave button on screen. A quick
/// switch left the first room connected under the second channel's name. And
/// the two shared one keyring, so one channel's load could clear the other's
/// keys.
///
/// So every step runs after the one before it has finished ([run]), and each
/// press takes a new turn ([begin]) that makes every earlier one stale. A
/// join still waiting asks [isCurrent] after each wait, and stands down if
/// it is not, closing whatever room it opened.
class CallSteps {
  final SerialQueue _queue = SerialQueue(label: '[LiveKit] call steps');
  int _turn = 0;

  /// A new press: everything begun before it is stale from now on.
  int begin() => ++_turn;

  /// Whether [turn] is still the latest press.
  bool isCurrent(int turn) => turn == _turn;

  /// Runs [step] once every step before it has finished.
  Future<void> run(Future<void> Function() step) => _queue.add(step);
}
