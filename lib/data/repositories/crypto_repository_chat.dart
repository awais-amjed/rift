part of 'crypto_repository.dart';

/// Chat / E2E-messaging crypto (ARCHITECTURE.md §4).
///
/// Key hierarchy:
/// - Chat identity: X25519 keypair per host, derived from the master seed with
///   the `"$host:chat:$version"` context — domain-separated from the Ed25519
///   auth identity (`"$host:$version"`), same recovery story.
/// - DM key (Design 1): static-static DH between the two chat identities,
///   then HMAC into an AES key. Symmetric — both sides derive the same key.
/// - Channel key (Design 2): random 32 bytes, sealed per member via
///   ephemeral-static DH ([wrapKey]/[unwrapKey]).
/// - Every message is sealed into a [MessageEnvelope]: AES-256-GCM +
///   mandatory Ed25519 signature over [MessageEnvelope.signedPayload].
mixin _ChatCryptoMixin {
  // Implemented by CryptoRepository.
  Future<Uint8List> hmacSha256({
    required Uint8List key,
    required String message,
  });
  Future<({Uint8List ciphertext, Uint8List iv})> encrypt({
    required String plaintext,
    required Uint8List key,
  });
  Future<String> decrypt({
    required Uint8List ciphertext,
    required Uint8List key,
    required Uint8List iv,
  });

  // ──────────────────────────────────────────────────────────
  // X25519 — Chat identity derivation
  // ──────────────────────────────────────────────────────────

  /// Derive the host-specific chat encryption identity from the master seed.
  ///
  /// childSeed = HMAC-SHA256(masterSeed, "host:chat:version")
  Future<ChatIdentity> deriveChatIdentity({
    required Uint8List masterSeed,
    required String host,
    String version = 'v1',
  }) async {
    final childSeed = await hmacSha256(
      key: masterSeed,
      message: '$host:chat:$version',
    );

    final x = X25519();
    final keyPair = await x.newKeyPairFromSeed(childSeed);
    final publicKey = await keyPair.extractPublicKey();

    return ChatIdentity(
      keyPair: keyPair,
      publicKeyBytes: Uint8List.fromList(publicKey.bytes),
    );
  }

  // ──────────────────────────────────────────────────────────
  // DM key — Design 1 (encrypt to identity)
  // ──────────────────────────────────────────────────────────

  /// Derive the shared DM message key between our chat identity and a peer's
  /// public key. DH is commutative, so both parties derive the same key.
  ///
  /// The raw DH output is never used directly:
  /// key = HMAC-SHA256(sharedSecret, "dm:v1")
  Future<Uint8List> deriveDmKey({
    required SimpleKeyPair myKeyPair,
    required Uint8List theirPublicKey,
  }) async {
    final x = X25519();
    final shared = await x.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(
        theirPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final sharedBytes = Uint8List.fromList(await shared.extractBytes());
    return hmacSha256(key: sharedBytes, message: 'dm:v1');
  }

  // ──────────────────────────────────────────────────────────
  // Channel key — Design 2 (wrapped channel key)
  // ──────────────────────────────────────────────────────────

  /// Generate a random 256-bit symmetric channel key.
  Uint8List generateChannelKey() => CryptoRepository._secureRandomBytes(32);

  /// Seal [key] to [recipientPublicKey] (ephemeral-static DH, sealed-box
  /// style): a fresh ephemeral X25519 keypair DHs with the recipient's public
  /// key; the result keys an AES-GCM encryption of [key]. Only the recipient's
  /// private key can unwrap. Used for channel-keyring entries.
  Future<WrappedKey> wrapKey({
    required Uint8List key,
    required Uint8List recipientPublicKey,
  }) async {
    final x = X25519();
    final ephemeral = await x.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();

    final shared = await x.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        recipientPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await hmacSha256(
      key: Uint8List.fromList(await shared.extractBytes()),
      message: 'wrap:v1',
    );

    final sealed = await encrypt(
      plaintext: CryptoRepository.toBase64(key),
      key: wrappingKey,
    );

    return WrappedKey(
      ephemeralPublicKey:
          CryptoRepository.toBase64(Uint8List.fromList(ephemeralPublic.bytes)),
      ciphertext: CryptoRepository.toBase64(sealed.ciphertext),
      nonce: CryptoRepository.toBase64(sealed.iv),
    );
  }

  /// Unwrap a key sealed to us with [wrapKey], using our chat identity's
  /// private key. Throws on tampering (AES-GCM auth failure).
  Future<Uint8List> unwrapKey({
    required WrappedKey wrapped,
    required SimpleKeyPair myKeyPair,
  }) async {
    final x = X25519();
    final shared = await x.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(
        CryptoRepository.fromBase64(wrapped.ephemeralPublicKey),
        type: KeyPairType.x25519,
      ),
    );
    final wrappingKey = await hmacSha256(
      key: Uint8List.fromList(await shared.extractBytes()),
      message: 'wrap:v1',
    );

    final keyB64 = await decrypt(
      ciphertext: CryptoRepository.fromBase64(wrapped.ciphertext),
      key: wrappingKey,
      iv: CryptoRepository.fromBase64(wrapped.nonce),
    );
    return CryptoRepository.fromBase64(keyB64);
  }

  // ──────────────────────────────────────────────────────────
  // Message envelope — seal / open
  // ──────────────────────────────────────────────────────────

  /// Encrypt [plaintext] with [messageKey] and sign the result with the
  /// sender's Ed25519 [signingKeyPair] (the existing server auth identity).
  /// [contextId] is the channel/conversation id — bound into the signature so
  /// the envelope can't be replayed elsewhere.
  Future<MessageEnvelope> sealMessage({
    required String plaintext,
    required Uint8List messageKey,
    required SimpleKeyPair signingKeyPair,
    required String contextId,
    required int keyVersion,
  }) async {
    final sealed = await encrypt(plaintext: plaintext, key: messageKey);
    final ciphertextB64 = CryptoRepository.toBase64(sealed.ciphertext);
    final nonceB64 = CryptoRepository.toBase64(sealed.iv);

    final payload = MessageEnvelope.signedPayload(
      contextId: contextId,
      keyVersion: keyVersion,
      nonce: nonceB64,
      ciphertext: ciphertextB64,
    );
    final signature = await Ed25519().sign(
      utf8.encode(payload),
      keyPair: signingKeyPair,
    );

    return MessageEnvelope(
      ciphertext: ciphertextB64,
      nonce: nonceB64,
      signature: CryptoRepository.toBase64(
        Uint8List.fromList(signature.bytes),
      ),
      keyVersion: keyVersion,
    );
  }

  /// Verify [envelope]'s signature against the sender's Ed25519 public key,
  /// then decrypt. Returns null if the signature doesn't verify — an unsigned
  /// or forged message is never surfaced (locked decision, ARCHITECTURE.md §4).
  /// Throws on AES-GCM auth failure (valid signature but corrupted body).
  Future<String?> openMessage({
    required MessageEnvelope envelope,
    required Uint8List messageKey,
    required Uint8List senderPublicKey,
    required String contextId,
  }) async {
    final payload = MessageEnvelope.signedPayload(
      contextId: contextId,
      keyVersion: envelope.keyVersion,
      nonce: envelope.nonce,
      ciphertext: envelope.ciphertext,
    );
    final valid = await Ed25519().verify(
      utf8.encode(payload),
      signature: Signature(
        CryptoRepository.fromBase64(envelope.signature),
        publicKey: SimplePublicKey(
          senderPublicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!valid) return null;

    return decrypt(
      ciphertext: CryptoRepository.fromBase64(envelope.ciphertext),
      key: messageKey,
      iv: CryptoRepository.fromBase64(envelope.nonce),
    );
  }
}
