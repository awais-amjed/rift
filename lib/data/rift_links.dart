/// Rift's own pages on the web, which the app points people to.
///
/// In one place because they are promises the app makes in several screens
/// — the welcome page, About, the create-server form — and a page that moves
/// on the website should be one edit here, not a search.
class RiftLinks {
  RiftLinks._();

  /// What Rift is, for somebody who installed it from a store listing and
  /// has nothing else to go on.
  static const String website = 'https://joinrift.app/';

  /// Setting up a server of your own: the part a new user is least likely to
  /// guess from the app itself.
  static const String selfHostingGuide = 'https://docs.joinrift.app/install/';

  static const String privacyPolicy = 'https://joinrift.app/privacy-policy/';
}
