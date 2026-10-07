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
/// - Key links: each channel key version sealed under the next ([sealKeyLink]).
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
      ephemeralPublicKey: CryptoRepository.toBase64(
        Uint8List.fromList(ephemeralPublic.bytes),
      ),
      ciphertext: CryptoRepository.toBase64(sealed.ciphertext),
      nonce: CryptoRepository.toBase64(sealed.iv),
    );
  }

  /// Seal [key] to every member in [members] and shape the results as
  /// channel-keyring rows for `post_channel_keys`.
  ///
  /// Each member is a row carrying `user_id` and `chat_public_key`; the
  /// output is `{'user_id': …, …WrappedKey.toJson()}`. Bootstrapping a
  /// keyring, healing members who lack an entry, and the background sweep all
  /// need exactly this, and a keyring built even slightly differently by one
  /// of them would lock those members out of the channel.
  Future<List<Map<String, dynamic>>> sealKeyringEntries({
    required Uint8List key,
    required List<Map<String, dynamic>> members,
  }) async {
    final entries = <Map<String, dynamic>>[];
    for (final member in members) {
      final wrapped = await wrapKey(
        key: key,
        recipientPublicKey: CryptoRepository.fromBase64(
          member['chat_public_key'] as String,
        ),
      );
      entries.add({'user_id': member['user_id'], ...wrapped.toJson()});
    }
    return entries;
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
  // Key links — each channel key opens the one before it
  // ──────────────────────────────────────────────────────────

  /// Seal channel key version `newerVersion - 1` ([olderKey]) under version
  /// [newerVersion] ([newerKey]), so whoever holds the newer one can open the
  /// older without being sealed it. A rotation stores one; a link only reaches
  /// backwards, so it gives nothing to somebody the rotation left out.
  ///
  /// ```
  /// linkKey = HMAC-SHA256(newerKey, "keylink:v1")
  /// sealed  = AES-256-GCM(olderKey, linkKey, nonce,
  ///                       aad: "keylink:v1:<channelId>:<newerVersion>")
  /// ```
  ///
  /// The HMAC keeps the key that seals the link apart from the one that seals
  /// messages, and the associated data pins it to its channel and place in the
  /// chain, so it cannot be moved to stand for another version.
  Future<({String ciphertext, String nonce})> sealKeyLink({
    required Uint8List newerKey,
    required Uint8List olderKey,
    required String channelId,
    required int newerVersion,
  }) async {
    final box = await AesGcm.with256bits().encrypt(
      olderKey,
      secretKey: SecretKey(await hmacSha256(key: newerKey, message: 'keylink:v1')),
      aad: utf8.encode('keylink:v1:$channelId:$newerVersion'),
    );
    return (
      ciphertext: CryptoRepository.toBase64(
        Uint8List.fromList(box.concatenation(nonce: false)),
      ),
      nonce: CryptoRepository.toBase64(Uint8List.fromList(box.nonce)),
    );
  }

  /// Open a link made by [sealKeyLink]: version `newerVersion - 1` of the
  /// channel key. Throws when the link was sealed under another key, for
  /// another channel, or for another place in the chain.
  Future<Uint8List> openKeyLink({
    required Uint8List newerKey,
    required String ciphertext,
    required String nonce,
    required String channelId,
    required int newerVersion,
  }) async {
    final algorithm = AesGcm.with256bits();
    final sealed = CryptoRepository.fromBase64(ciphertext);
    final macLength = algorithm.macAlgorithm.macLength;
    final opened = await algorithm.decrypt(
      SecretBox(
        sealed.sublist(0, sealed.length - macLength),
        nonce: CryptoRepository.fromBase64(nonce),
        mac: Mac(sealed.sublist(sealed.length - macLength)),
      ),
      secretKey: SecretKey(await hmacSha256(key: newerKey, message: 'keylink:v1')),
      aad: utf8.encode('keylink:v1:$channelId:$newerVersion'),
    );
    return Uint8List.fromList(opened);
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
      signature: CryptoRepository.toBase64(Uint8List.fromList(signature.bytes)),
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
        publicKey: SimplePublicKey(senderPublicKey, type: KeyPairType.ed25519),
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
