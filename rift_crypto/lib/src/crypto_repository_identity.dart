part of 'crypto_repository.dart';

/// Identity crypto: the HMAC-SHA256 key ladder that turns one master seed
/// into every per-context key, and the SIWS message the server authenticates
/// a login with.
///
/// Every derivation here is domain-separated by its message string
/// (`"vault:v1"`, `"<host>:<serverId>:v1"`), which is what stops one
/// context's key from being usable in another.
mixin _IdentityCryptoMixin {
  // ──────────────────────────────────────────────────────────
  // HMAC-SHA256 — Identity derivation
  // ──────────────────────────────────────────────────────────

  /// Compute HMAC-SHA256(key, message) and return raw bytes.
  Future<Uint8List> hmacSha256({
    required Uint8List key,
    required String message,
  }) async {
    final algorithm = Hmac.sha256();
    final mac = await algorithm.calculateMac(
      utf8.encode(message),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(mac.bytes);
  }

  /// Derive the local vault encryption key from the master seed.
  ///
  /// key = HMAC-SHA256(masterSeed, "vault:v1")
  ///
  /// Always derivable from the locally-stored master seed — no password needed.
  /// Domain-separated with "vault:v1" to prevent key reuse across contexts.
  Future<Uint8List> deriveLocalVaultKey(Uint8List masterSeed) =>
      hmacSha256(key: masterSeed, message: 'vault:v1');

  /// Derive the key that seals the conversations this device keeps a copy of.
  ///
  /// key = HMAC-SHA256(masterSeed, "local-cache/messages:v1")
  ///
  /// A rung of its own rather than [deriveLocalVaultKey], so that nothing which
  /// can open the vault blob can open these, or the other way round. The `/`
  /// is there because no host can contain one, so the label cannot meet a
  /// `"<host>:…"` context however a server is named.
  Future<Uint8List> deriveMessageCacheKey(Uint8List masterSeed) =>
      hmacSha256(key: masterSeed, message: 'local-cache/messages:v1');

  /// Derive the full server identity from the master seed and host.
  ///
  /// Returns the Ed25519 keypair (for auth/signing) and the stable ID (for
  /// bans). When [serverId] is given the derivation is **scoped to that server**,
  /// so multiple servers sharing one Supabase host (project) each get a distinct
  /// SIWS identity — without it, two servers in one project would collide on
  /// `auth.uid()`. [serverId] is null only for the central host (one identity
  /// per host); that path is unchanged, preserving existing central keys.
  /// - childSeed = HMAC-SHA256(masterSeed, `"<host>[:<serverId>]:<version>"`)
  /// - stableId  = HMAC-SHA256(masterSeed, `"<host>[:<serverId>]:identity"`)
  Future<ServerIdentity> deriveServerIdentity({
    required Uint8List masterSeed,
    required String host,
    String? serverId,
    String version = 'v1',
  }) async {
    final scope = serverId == null ? host : '$host:$serverId';

    // Derive child seed → Ed25519 keypair
    final childSeed = await hmacSha256(
      key: masterSeed,
      message: '$scope:$version',
    );

    final ed = Ed25519();
    final keyPair = await ed.newKeyPairFromSeed(childSeed);
    final publicKey = await keyPair.extractPublicKey();

    // Derive stable ID
    final stableIdBytes = await hmacSha256(
      key: masterSeed,
      message: '$scope:identity',
    );

    return ServerIdentity(
      keyPair: keyPair,
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
      stableId: CryptoRepository.toBase64(stableIdBytes),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Ed25519 — Sign-in-with-Web3 (SIWS) login signing
  // ──────────────────────────────────────────────────────────

  /// The domain and URI written into every SIWS message, for every server.
  ///
  /// **Deliberately constant, and deliberately not the server's address.**
  /// GoTrue's web3 grant refuses most real addresses: the domain must match
  /// `^(localhost|<dotted-name>.<tld>)(:port)?$` — so a bare LAN IP like
  /// `192.168.1.6` is rejected outright — and anything other than `localhost`
  /// additionally has to be **https**, be listed in the stack's `SITE_URL` /
  /// `URI_ALLOW_LIST`, and repeat its port in the domain. Signing the real
  /// address would mean a Rift server could only be reached over HTTPS at a
  /// name its operator had also configured GoTrue to expect.
  ///
  /// Nothing is lost by faking it. These two fields exist so a *wallet* can
  /// tell you which site is asking you to sign; Rift has no wallet and no
  /// third-party sites — the key is derived per `(host, serverId)`, the message
  /// is posted only to the host it was derived for, and GoTrue identifies the
  /// caller by the signing key, never by this text.
  static const _siwsDomain = 'localhost';
  static const _siwsUri = 'http://localhost';

  /// Build and sign a Sign-in-with-Solana (SIWS) message with an Ed25519
  /// keypair. The base58 of the public key is the "Solana address" GoTrue keys
  /// the identity on. Returns the exact message that was signed plus the base64
  /// signature — both posted to the `login` function.
  ///
  /// Takes no address: see [_siwsDomain] for why the message names `localhost`
  /// whatever server it is for.
  ///
  /// `Chain ID: solana:mainnet` and the base64 signature encoding are required
  /// by GoTrue's web3 grant. `API.md` in `rift-self-host` explains which of its
  /// four gates each field is there to clear.
  ///
  /// [issuedAt] defaults to now. GoTrue refuses a message dated more than ten
  /// minutes from its own clock, so a device whose clock is wrong signs at the
  /// server's time instead (`siwsSignIn`).
  Future<({String message, String signatureBase64})> signSiws({
    required SimpleKeyPair keyPair,
    required Uint8List publicKeyBytes,
    DateTime? issuedAt,
  }) async {
    final address = CryptoRepository.toBase58(publicKeyBytes);
    final nonce = CryptoRepository.toBase64(
      CryptoRepository._secureRandomBytes(12),
    ).replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    final issued = (issuedAt ?? DateTime.now()).toUtc().toIso8601String();

    final message =
        '$_siwsDomain wants you to sign in with your Solana account:\n'
        '$address\n'
        '\n'
        'Sign in to Rift.\n'
        '\n'
        'URI: $_siwsUri\n'
        'Version: 1\n'
        'Chain ID: solana:mainnet\n'
        'Nonce: $nonce\n'
        'Issued At: $issued';

    final ed = Ed25519();
    final signature = await ed.sign(utf8.encode(message), keyPair: keyPair);
    return (
      message: message,
      signatureBase64: CryptoRepository.toBase64(
        Uint8List.fromList(signature.bytes),
      ),
    );
  }
}
