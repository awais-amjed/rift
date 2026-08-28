part of 'crypto_repository.dart';

/// Command crypto: **signed, not sealed** (BOTS.md §4).
///
/// Its own file because it is the one thing in this repository that
/// deliberately does not encrypt. A `/` command is addressed to a bot, a bot
/// holds no channel key and never will, so sealing one would produce a message
/// it could never open.
///
/// What does not change is the signature. Being readable is not a reason to be
/// unattributable: a command carries a person's name in a room full of people,
/// and the canonical payload still binds it to a channel and a key version, so
/// one cannot be replayed into another conversation.
mixin _CommandCryptoMixin {
  // ──────────────────────────────────────────────────────────
  // Commands — signed, not sealed (BOTS.md §4)
  // ──────────────────────────────────────────────────────────

  /// A `/` command as an envelope: **plain text, still signed**.
  ///
  /// Not sealed, because the bot it is addressed to holds no channel key and
  /// never will — a sealed command is one it could never open. Signed all the
  /// same, because being readable is not a reason to be unattributable: this
  /// message carries a person's name in a room full of people, and without a
  /// signature the server could put any words under it.
  ///
  /// Key version 0 and an empty nonce, both of which go into the canonical
  /// payload, so a command signed for one channel cannot be replayed into
  /// another any more than a sealed message can.
  Future<MessageEnvelope> signPlaintext({
    required String plaintext,
    required SimpleKeyPair signingKeyPair,
    required String contextId,
  }) async {
    final signature = await Ed25519().sign(
      utf8.encode(
        MessageEnvelope.signedPayload(
          contextId: contextId,
          keyVersion: 0,
          nonce: '',
          ciphertext: plaintext,
        ),
      ),
      keyPair: signingKeyPair,
    );
    return MessageEnvelope(
      ciphertext: plaintext,
      nonce: '',
      signature: CryptoRepository.toBase64(Uint8List.fromList(signature.bytes)),
      keyVersion: 0,
    );
  }

  /// Whether a plaintext command really came from [senderPublicKey].
  ///
  /// The counterpart to [signPlaintext], and the reason a member's command is
  /// checked while a webhook's message is not: a webhook has no key and is
  /// never shown as a person, but a command is attributed to whoever sent it.
  /// An unverifiable one is dropped exactly like an unverifiable sealed
  /// message — same rule, same silence.
  Future<bool> verifyPlaintext({
    required MessageEnvelope envelope,
    required Uint8List senderPublicKey,
    required String contextId,
  }) async {
    try {
      return await Ed25519().verify(
        utf8.encode(
          MessageEnvelope.signedPayload(
            contextId: contextId,
            keyVersion: envelope.keyVersion,
            nonce: envelope.nonce,
            ciphertext: envelope.ciphertext,
          ),
        ),
        signature: Signature(
          CryptoRepository.fromBase64(envelope.signature),
          publicKey: SimplePublicKey(
            senderPublicKey,
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
