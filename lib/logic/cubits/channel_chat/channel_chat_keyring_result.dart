part of 'channel_chat_cubit.dart';

enum _KeyringStatus { ready, waiting, error }

/// How a keyring load ended, and — when it failed — why.
///
/// The reason travels with the outcome rather than being logged and dropped:
/// nearly every failure here is really "the server didn't answer", and the
/// person waiting on the channel deserves to be told that instead of being
/// pointed at the encryption.
class _KeyringResult {
  final _KeyringStatus status;

  /// Set only when [status] is [_KeyringStatus.error].
  final ChatFailure? failure;

  const _KeyringResult.ready() : status = _KeyringStatus.ready, failure = null;

  const _KeyringResult.waiting()
    : status = _KeyringStatus.waiting,
      failure = null;

  const _KeyringResult.failed(ChatFailure this.failure)
    : status = _KeyringStatus.error;

  bool get isReady => status == _KeyringStatus.ready;
  bool get isWaiting => status == _KeyringStatus.waiting;
  bool get isFailed => status == _KeyringStatus.error;
}
