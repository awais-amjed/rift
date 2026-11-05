import 'dart:async';

/// One press of Share, from the press until the share starts or is given up.
///
/// The desktop's window picker is not ours, so it does not block the Share
/// button the way our dialogs do, and it can go away without saying so. A
/// second press therefore gives up the attempt before it
/// ([ScreenshareCubit.beginAttempt]), and whatever that attempt was waiting on
/// closes ([whenAbandoned]). Nothing of it may carry on later, over a share
/// that has started since.
class ShareAttempt {
  final Completer<void> _abandoned = Completer();

  bool get abandoned => _abandoned.isCompleted;

  Future<void> get whenAbandoned => _abandoned.future;

  void abandon() {
    if (!abandoned) _abandoned.complete();
  }
}
