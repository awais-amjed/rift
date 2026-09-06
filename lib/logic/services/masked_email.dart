/// An email address with the part that identifies somebody hidden.
///
/// `hey.hasan@gmail.com` becomes `h•••••@gmail.com`: the first letter, so
/// the reader can tell which of their accounts it is, and the domain, which
/// is not a secret. Everything that would let a viewer on a shared screen
/// write to the address is dots.
class MaskedEmail {
  const MaskedEmail._();

  static const String _dot = '•';

  static String of(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return _dot * email.length.clamp(3, 8);
    final local = email.substring(0, at);
    final domain = email.substring(at);
    final shown = local.substring(0, 1);
    final hidden = _dot * (local.length - 1).clamp(3, 8);
    return '$shown$hidden$domain';
  }
}
