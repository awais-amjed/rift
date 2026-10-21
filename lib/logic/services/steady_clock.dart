/// The time now, on a clock that only counts time passing, for the timers
/// that show how long a call has run.
///
/// The PC's own clock can be set, or corrected by a time sync, partway
/// through a call, and a timer reading it jumps by as much: one counted
/// seven hours into a call that was minutes old. This one starts from the
/// PC's time once, when first read, and from then on only adds what a
/// stopwatch measured, so nothing done to the PC's clock moves it. Its
/// readings are only for comparing with each other; a time from anywhere
/// else comes in through [fromWall].
class SteadyClock {
  const SteadyClock._();

  static final DateTime _origin = DateTime.now();
  static final Stopwatch _watch = Stopwatch()..start();

  static DateTime now() => _origin.add(_watch.elapsed);

  /// [wall], a time from the PC's clock or a server's, on this one: as long
  /// ago now as it is by the PC's clock. A clock that is wrong then is wrong
  /// in it too, but whatever the PC's clock does afterwards is not.
  static DateTime fromWall(DateTime wall) =>
      now().subtract(DateTime.now().difference(wall));
}
