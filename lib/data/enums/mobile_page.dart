/// A screen pushed over the list on a phone.
///
/// On a desktop every one of these is a pane that sits beside the list. A phone
/// has room for one thing at a time, so each becomes a page you go into and
/// come back out of — see `MobilePageStack` for how they stack.
enum MobilePage {
  /// The voice call you are in. Leaving the page does not leave the call.
  call,

  /// A text channel's chat.
  channelChat,

  /// A conversation with a member of this server.
  serverDm,

  /// A conversation on the central tier.
  centralDm,

  /// Friends and pending requests on the central tier.
  friends;

  /// Everything but the call: somewhere you read and write, only one of which
  /// is ever open, because each is backed by one cubit's single open slot.
  bool get isConversation => this != MobilePage.call;
}
