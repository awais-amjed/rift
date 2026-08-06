import '../../data/classes/api_response.dart';
import '../../data/enums/error_code.dart';

/// A chat that would not open, described for the person who hit it.
///
/// Opening a channel means fetching its keyring and unwrapping our entry, and
/// every step of that can fail for a different reason — the server is down, the
/// vault is locked, nobody has published a key yet. Collapsing them all into
/// "Could not load the channel key" tells the reader nothing they can act on,
/// and points at the encryption when the actual problem is usually that the
/// server isn't running.
///
/// The voice side has the same shape in `ConnectionFailure`; the two stay
/// separate because they translate entirely different errors.
class ChatFailure {
  /// Short statement of what failed. Reads as a headline, no trailing period.
  final String title;

  /// One or two sentences: what it means, and what to do about it.
  final String message;

  /// Whether nothing answered at the server's address. Purely about what
  /// happened — the UI decides that this is the case worth a different icon.
  final bool offline;

  const ChatFailure({
    required this.title,
    required this.message,
    this.offline = false,
  });

  /// The open failed but nothing recorded why. Should not happen.
  const ChatFailure.unknown()
    : title = 'Could not open this channel',
      message = 'Something went wrong.',
      offline = false;

  /// No server is selected — a UI state, not a server problem.
  const ChatFailure.noServer()
    : title = 'No server selected',
      message = 'Pick a server before opening one of its channels.',
      offline = false;

  /// The vault is locked, so the chat identity that unwraps channel keys can't
  /// be derived.
  const ChatFailure.vaultLocked()
    : title = 'Your vault is locked',
      message =
          'Rift needs the vault open to unwrap this channel\'s encryption '
          'key. Unlock it and try again.',
      offline = false;

  /// The channel has no key yet and there is nobody keyed to seal a first one
  /// to — including us, which means our own chat key never reached the server.
  const ChatFailure.noKeyedMembers()
    : title = 'This channel has no key yet',
      message =
          'It needs a first encryption key, and no member has published a '
          'chat key to seal one to. That normally resolves itself once the '
          'server can be reached again.',
      offline = false;

  /// Two members bootstrapped the channel's first key at once and the retry
  /// still lost.
  const ChatFailure.keyringConflict()
    : title = 'Could not settle this channel\'s key',
      message =
          'Another member set the first encryption key at the same moment. '
          'Trying again picks up theirs.',
      offline = false;

  /// Translates a failed server call.
  ///
  /// The unreachable message is passed through rather than rewritten: the
  /// repository already phrases it for a person, and it says whether the server
  /// refused the socket or just never answered — a distinction the error code
  /// alone loses.
  factory ChatFailure.fromResponse(APIResponse response) {
    final message = response.error;

    if (response.errorCode == ErrorCode.serverUnreachable) {
      return ChatFailure(
        title: 'Cannot reach this server',
        message:
            message ??
            "Can't reach this server. It may be offline, or check your "
                'connection.',
        offline: true,
      );
    }

    if (response.errorCode == ErrorCode.permissionDenied) {
      return const ChatFailure(
        title: 'No access to this channel',
        message:
            'The server would not hand over this channel\'s key. Your access '
            'to it may have changed.',
      );
    }

    if (response.errorCode == ErrorCode.channelNotFound) {
      return const ChatFailure(
        title: 'This channel is gone',
        message: 'It was deleted, or it belongs to a different server.',
      );
    }

    return ChatFailure(
      title: 'Could not open this channel',
      message: message ?? 'The server did not say why.',
    );
  }
}
