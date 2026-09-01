import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// The formats a second implementation has to match, checked against numbers
/// rather than against the code that produced them. See `WIRE.md`.
///
/// Two implementations of a canonical payload are two things that can disagree,
/// and the disagreement does not look like an error: a message signed over a
/// payload that differs by one character stores fine, verifies as false, and
/// renders as nothing. The sender watches it send. Nobody else ever sees it.
///
/// So these are not really tests of the crypto — they are a tripwire on the
/// *format*. A refactor that changes a separator, a scope string, or the order
/// of two ids fails here and nowhere else, because everything else in the app
/// signs and verifies with the same changed code and agrees with itself.
///
/// If one of these fails, the question is not "how do I make it pass". It is
/// "did I mean to change the wire format", and if the answer is yes the vectors
/// are regenerated deliberately with `dart run tool/gen_wire_vectors.dart`.
void main() {
  final crypto = CryptoRepository();
  final vectors =
      jsonDecode(File('test/wire_vectors.json').readAsStringSync())
          as Map<String, dynamic>;

  final seed = CryptoRepository.fromBase64(vectors['seed_base64'] as String);

  Map<String, dynamic> section(String name) =>
      vectors[name] as Map<String, dynamic>;

  group('the key ladder', () {
    test('HMAC-SHA256 over the domain strings', () async {
      final hmac = section('hmac');
      for (final entry in hmac.entries) {
        final message = entry.key == 'vault_key'
            ? 'vault:v1'
            : entry.key.substring('context_'.length);
        final got = await crypto.hmacSha256(key: seed, message: message);
        expect(
          CryptoRepository.toBase64(got),
          entry.value,
          reason: 'HMAC over "$message" moved',
        );
      }
    });

    test('a server identity is scoped to host *and* server', () async {
      // Without the server id, two servers sharing one Supabase project would
      // derive the same key and collide on `auth.uid()`.
      final v = section('server_identity');
      final identity = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: v['host'] as String,
        serverId: v['server_id'] as String,
      );
      expect(
        CryptoRepository.toBase64(identity.publicKeyBytes),
        v['public_key_base64'],
      );
      expect(identity.stableId, v['stable_id']);
    });

    test('the base58 address SIWS signs is the same key', () async {
      final v = section('server_identity');
      final identity = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: v['host'] as String,
        serverId: v['server_id'] as String,
      );
      expect(
        CryptoRepository.toBase58(identity.publicKeyBytes),
        v['public_key_base58'],
      );
    });

    test('the central identity has no server in its scope', () async {
      // One identity per host, and it must stay that way: changing this
      // orphans every existing central account.
      final v = section('central_identity');
      final identity = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: v['host'] as String,
      );
      expect(
        CryptoRepository.toBase64(identity.publicKeyBytes),
        v['public_key_base64'],
      );
      expect(identity.stableId, v['stable_id']);
    });

    test('the chat identity is per host and pinned at v1', () async {
      // Deliberately not scoped to a server and deliberately not following the
      // auth key's version: rotating it would make old messages unreadable.
      final v = section('chat_identity');
      final identity = await crypto.deriveChatIdentity(
        masterSeed: seed,
        host: v['host'] as String,
      );
      expect(
        CryptoRepository.toBase64(identity.publicKeyBytes),
        v['public_key_base64'],
      );
    });
  });

  group('the signed payload', () {
    final v = section('signed_payload');

    test('a channel message', () {
      expect(
        MessageEnvelope.signedPayload(
          contextId: 'aaaa1111-0000-4000-8000-000000000001',
          keyVersion: 3,
          nonce: 'bm9uY2U=',
          ciphertext: 'Y2lwaGVy',
        ),
        v['channel'],
      );
    });

    test('a bot message, signed but not sealed', () {
      // Version 0 and an empty nonce, which leaves two colons together. A port
      // that omitted the empty field instead would produce a payload one
      // character shorter and a signature nothing verifies.
      expect(
        MessageEnvelope.signedPayload(
          contextId: 'aaaa1111-0000-4000-8000-000000000001',
          keyVersion: 0,
          nonce: '',
          ciphertext: '/echo hello',
        ),
        v['bot_plaintext'],
      );
      expect(v['bot_plaintext'], contains(':0::'));
    });

    test('a DM context is sorted, so both sides derive the same one', () {
      const a = '00000000-0000-4000-8000-000000000001';
      const b = 'ffffffff-0000-4000-8000-000000000002';
      expect(MessageEnvelope.conversationContext(a, b), v['dm_context']);
      expect(MessageEnvelope.conversationContext(b, a), v['dm_context']);
    });
  });

  group('the sealed key a bot is handed', () {
    // A bot has to encrypt its own media to be heard in an end-to-end
    // encrypted call, and the key it uses is sealed to it by a member. This is
    // the one thing a bot ever opens (BOTS.md §6b).

    test('unwraps to the key that was sealed', () async {
      // The blob is frozen rather than regenerated: `wrapKey` picks a random
      // ephemeral key, so there are no reproducible bytes to compare. What is
      // reproducible is that this exact blob still opens — which is what a
      // change to the wrap format would break.
      final v = section('wrapped_key');
      final identity = await crypto.deriveChatIdentity(
        masterSeed: seed,
        host: section('chat_identity')['host'] as String,
      );
      final key = await crypto.unwrapKey(
        wrapped: WrappedKey.fromJson(v),
        myKeyPair: identity.keyPair,
      );
      expect(CryptoRepository.toBase64(key), v['key_base64']);
    });

    test(
      'the key a bot speaks with cannot be walked back to the channel key',
      () async {
        // Members derive this; the bot receives only the result. HMAC is what
        // makes "audible but deaf" expressible at all — with one shared room key
        // it is not (BOTS.md §2).
        final v = section('bot_voice_key');
        final channelKey = CryptoRepository.fromBase64(
          section('wrapped_key')['key_base64'] as String,
        );
        final derived = await crypto.hmacSha256(
          key: channelKey,
          message: 'voicebot:v1:${v['bot_id']}',
        );
        expect(CryptoRepository.toBase64(derived), v['key_base64']);
        expect(
          CryptoRepository.toBase64(derived),
          isNot(section('wrapped_key')['key_base64']),
        );
      },
    );
  });

  test('a DM key is the exchange, not a stored secret', () async {
    // Both ends derive it from opposite halves, so there is nothing to
    // distribute and nothing for the server to hold — and no round trip in
    // which two implementations could notice they disagree.
    final v = section('dm_key');
    final mine = await crypto.deriveChatIdentity(
      masterSeed: seed,
      host: section('chat_identity')['host'] as String,
    );
    final key = await crypto.deriveDmKey(
      myKeyPair: mine.keyPair,
      theirPublicKey: CryptoRepository.fromBase64(
        v['peer_chat_public_key'] as String,
      ),
    );
    expect(CryptoRepository.toBase64(key), v['key_base64']);
  });

  test('a signature over all of it', () async {
    // Ed25519 is deterministic, so this one line proves the key ladder and the
    // payload construction at the same time: get either wrong and the bytes
    // differ.
    final identity = await crypto.deriveServerIdentity(
      masterSeed: seed,
      host: section('server_identity')['host'] as String,
      serverId: section('server_identity')['server_id'] as String,
    );
    final signature = await Ed25519().sign(
      utf8.encode(section('signed_payload')['channel'] as String),
      keyPair: identity.keyPair,
    );
    expect(
      CryptoRepository.toBase64(Uint8List.fromList(signature.bytes)),
      section('signature')['base64'],
    );
  });

  test('and it verifies against the published key', () async {
    // The half a bot's client actually runs. A vector that only checked the
    // signing side would pass on an implementation nobody could read.
    final identity = await crypto.deriveServerIdentity(
      masterSeed: seed,
      host: section('server_identity')['host'] as String,
      serverId: section('server_identity')['server_id'] as String,
    );
    final ok = await Ed25519().verify(
      utf8.encode(section('signed_payload')['channel'] as String),
      signature: Signature(
        CryptoRepository.fromBase64(section('signature')['base64'] as String),
        publicKey: SimplePublicKey(
          identity.publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    expect(ok, isTrue);
  });
}
