import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/member_report.dart';
import 'package:rift/data/enums/member_report_reason.dart';
import 'package:rift/data/repositories/secure_storage_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/reported_message_opener.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// A message sent in the clear is still put under somebody's name on the
/// Reports page, so it is checked against their signature exactly as the chat
/// checks it (`PlainRows.open`). Only a webhook's, which names no person, is
/// shown unchecked.
class _NoStorage extends SecureStorageRepository {
  @override
  Future<String?> getMasterSeed() async => null;
}

void main() {
  final crypto = CryptoRepository();
  const channelId = 'c1';
  late ReportedMessageOpener opener;
  late ServerIdentity author;

  setUp(() async {
    opener = ReportedMessageOpener(
      session: SessionRepository(),
      vaultCubit: VaultCubit(storage: _NoStorage()),
      crypto: crypto,
    );
    author = await crypto.deriveServerIdentity(
      masterSeed: Uint8List(32)..fillRange(0, 32, 7),
      host: 'h',
      serverId: 's1',
    );
  });

  MemberReport reportOf({
    required String ciphertext,
    String? signature,
    String? targetId = 'u1',
    String? publicKey,
    String? originName,
  }) => MemberReport(
    id: 1,
    createdAt: DateTime.utc(2026, 11, 22),
    reason: MemberReportReason.fromString('spam'),
    targetId: targetId,
    target: targetId == null
        ? null
        : ReportPerson(
            displayName: 'Ana',
            username: 'ana',
            publicKey: publicKey,
          ),
    message: ReportedMessage(
      id: 9,
      channelId: channelId,
      createdAt: DateTime.utc(2026, 11, 22),
      ciphertext: ciphertext,
      signature: signature,
      keyVersion: 0,
      originName: originName,
    ),
  );

  test('a member\'s message in the clear, signed by them, is shown', () async {
    final envelope = await crypto.signPlaintext(
      plaintext: 'hello',
      signingKeyPair: author.keyPair,
      contextId: channelId,
    );
    final opened = await opener.open(
      reportOf(
        ciphertext: envelope.ciphertext,
        signature: envelope.signature,
        publicKey: CryptoRepository.toBase64(author.publicKeyBytes),
      ),
      serverId: 's1',
    );
    expect(opened.content, ReportedContent.signedPlain);
    expect(opened.message?.text, 'hello');
  });

  test(
    'words in the clear under a member\'s name, unsigned, are not',
    () async {
      final envelope = await crypto.signPlaintext(
        plaintext: 'hello',
        signingKeyPair: author.keyPair,
        contextId: channelId,
      );
      final opened = await opener.open(
        reportOf(
          ciphertext: 'words they never sent',
          signature: envelope.signature,
          publicKey: CryptoRepository.toBase64(author.publicKeyBytes),
        ),
        serverId: 's1',
      );
      expect(opened.content, ReportedContent.unverified);
      expect(opened.message, isNull);
    },
  );

  test('a member with no key to check against is not believed', () async {
    final opened = await opener.open(
      reportOf(ciphertext: 'hello'),
      serverId: 's1',
    );
    expect(opened.content, ReportedContent.unverified);
  });

  test(
    'a webhook\'s message names nobody, so it is shown as it came',
    () async {
      final opened = await opener.open(
        reportOf(ciphertext: 'build failed', targetId: null, originName: 'CI'),
        serverId: 's1',
      );
      expect(opened.content, ReportedContent.plain);
      expect(opened.message?.text, 'build failed');
    },
  );
}
