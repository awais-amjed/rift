import 'chat_failure.dart';

/// How a keyring load ended.
///
/// "Waiting" is not a failure: it is the state of a member who has joined a
/// channel nobody has sealed the current key to yet. Somebody else's client
/// heals them, and the screen that is waiting refetches when the doorbell
/// rings — so it needs its own answer rather than an error nobody can act on.
class KeyringOutcome {
  final bool isReady;
  final bool isWaiting;
  final ChatFailure? failure;

  const KeyringOutcome.ready()
    : isReady = true,
      isWaiting = false,
      failure = null;

  const KeyringOutcome.waiting()
    : isReady = false,
      isWaiting = true,
      failure = null;

  const KeyringOutcome.failed(ChatFailure this.failure)
    : isReady = false,
      isWaiting = false;
}
