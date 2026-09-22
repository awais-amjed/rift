import '../helper_methods.dart';

/// Runs asynchronous steps one at a time, in submission order.
///
/// For work that tears something down and builds it back up, where two runs
/// overlapping is not a slow path but a correctness bug: both get past the
/// teardown, both build, and only the last one's handle is kept. The other is
/// left running with nothing holding a reference to stop it.
///
/// A step that throws is reported and swallowed rather than propagated —
/// otherwise the failure would be the queue's tail, and every step submitted
/// afterwards would inherit it.
class SerialQueue {
  final String _label;

  Future<void> _tail = Future.value();

  SerialQueue({String label = 'SerialQueue'}) : _label = label;

  /// Queues [step] behind everything already submitted. The returned future
  /// completes when *this* step has finished — including when it failed.
  Future<void> add(Future<void> Function() step) {
    final next = _tail
        .then((_) => step())
        .catchError(
          (Object e) => HelperMethods.printDebug('$_label: step failed – $e'),
        );
    _tail = next;
    return next;
  }

  /// Completes when everything queued so far has finished. Anything submitted
  /// after this call is not waited on.
  Future<void> get idle => _tail;
}
