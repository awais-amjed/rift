part of 'crypto_repository.dart';

/// The recovery key: a second, independent way to unwrap the master seed.
///
/// The password protects the seed by way of `Argon2id(password, salt)`. A
/// recovery key does exactly the same thing with the same primitive — a
/// separate blob, a separate salt, the same plaintext underneath. Neither
/// knows about the other, which is the whole point: forgetting one does not
/// cost you the seed, and neither one has to be derivable from anything the
/// server holds.
///
/// It is *not* a password hint and it is not a second factor. It is a spare
/// key to the same lock, and it must be treated like one.
mixin _RecoveryCryptoMixin {
  /// Crockford's base32, which is the reason this is readable at all.
  ///
  /// No `I`, `L`, `O` or `U`. The first three are dropped because a person
  /// copying a key off a screen cannot reliably tell them from `1` and `0`,
  /// and `U` is dropped because its absence keeps accidental words out of a
  /// string people will read aloud down a phone line.
  static const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

  /// Five groups of five. 25 characters over a 32-symbol alphabet is 125 bits
  /// of entropy — past any offline-guessing concern, and still short enough to
  /// write on paper without losing your place.
  static const int _groups = 5;
  static const int _groupLength = 5;

  /// Generate a fresh recovery key in display form: `XXXXX-XXXXX-…`.
  ///
  /// Every character is drawn from five bits of `Random.secure()`. The
  /// alphabet is exactly 32 symbols, so those five bits map onto it with no
  /// remainder and no modulo bias — the usual trap in "pick a random
  /// character" code, where an alphabet that is not a power of two quietly
  /// makes early letters more likely.
  String generateRecoveryKey() {
    final total = _groups * _groupLength;
    final bytes = CryptoRepository._secureRandomBytes(total);
    final chars = List<String>.generate(
      total,
      (i) => _alphabet[bytes[i] & 0x1F],
    );

    final buffer = StringBuffer();
    for (var g = 0; g < _groups; g++) {
      if (g > 0) buffer.write('-');
      buffer.write(
        chars.sublist(g * _groupLength, (g + 1) * _groupLength).join(),
      );
    }
    return buffer.toString();
  }

  /// Reduce a typed key to the exact string the KDF was fed.
  ///
  /// **This is the only form that may reach [CryptoRepository.deriveVaultKey].**
  /// Argon2id has no notion of "close enough", so every difference between
  /// what a person types and what was generated — a lowercase letter, a
  /// missing dash, a space pasted in from a document — is the difference
  /// between recovering the vault and being told the key is wrong. Each
  /// substitution below is a mistake somebody will actually make:
  ///
  /// - separators are dropped, so grouping is presentation and nothing else;
  /// - case is folded up, because the alphabet is upper-case only;
  /// - `I` and `L` become `1`, `O` becomes `0` — the characters Crockford
  ///   leaves out precisely because they get read as digits.
  ///
  /// Returns null when what is left is not a well-formed key, so a caller can
  /// say "that isn't a recovery key" before spending a second on Argon2id.
  String? normalizeRecoveryKey(String input) {
    final stripped = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-_]'), '')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('O', '0');

    if (stripped.length != _groups * _groupLength) return null;
    for (final unit in stripped.codeUnits) {
      if (!_alphabet.codeUnits.contains(unit)) return null;
    }
    return stripped;
  }

  /// Present a canonical key in the grouped form people are shown.
  ///
  /// Round-trips with [normalizeRecoveryKey]: the dashes carry no information,
  /// so a key may be stored ungrouped and displayed grouped without either
  /// form being more correct than the other.
  String formatRecoveryKey(String normalized) {
    final groups = <String>[];
    for (var i = 0; i < normalized.length; i += _groupLength) {
      groups.add(
        normalized.substring(
          i,
          i + _groupLength > normalized.length
              ? normalized.length
              : i + _groupLength,
        ),
      );
    }
    return groups.join('-');
  }
}
