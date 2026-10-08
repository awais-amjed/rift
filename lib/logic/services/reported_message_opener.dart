import 'package:rift_crypto/rift_crypto.dart';

import '../../data/classes/chat_message.dart';
import '../../data/classes/member_report.dart';
import '../../data/classes/message_body.dart';
import '../../data/repositories/session_repository.dart';
import '../cubits/server/server_cubit.dart';
import '../cubits/vault/vault_cubit.dart';
import '../helper_methods.dart';
import 'channel_keyring.dart';

/// What a reviewer's device made of a reported message.
enum ReportedContent {
  /// Opened with the channel key and signed by the member it names.
  verified,

  /// Sent in the clear — a webhook's, or a bot's — so there was nothing to
  /// open, and no one's key to check a webhook against.
  plain,

  /// Sealed under a key this device does not hold: a private channel the
  /// reviewer is not inside, or a key nobody has wrapped for them yet.
  locked,

  /// The signature does not match. Not shown — the same rule as a forged
  /// message anywhere (ARCHITECTURE.md §4) — only said.
  unverified,
}

/// Opens the sealed envelope a message report kept, with the reviewer's own
/// channel keys, and checks the author's signature.
///
/// The keys come from the same keyring a channel opens with, read-only: this
/// never bootstraps a key or heals anybody, because reading a report is not
/// joining the channel. One ring per channel, kept for as long as the reports
/// page lives, so a page of reports from one channel fetches its keys once.
class ReportedMessageOpener {
  final ServerCubit _serverCubit;
  final SessionRepository _session;
  final VaultCubit _vaultCubit;
  final CryptoRepository _crypto;
  final Map<String, ChannelKeyring> _rings = {};

  ReportedMessageOpener({
    required ServerCubit serverCubit,
    required SessionRepository session,
    required VaultCubit vaultCubit,
    CryptoRepository? crypto,
  }) : _serverCubit = serverCubit,
       _session = session,
       _vaultCubit = vaultCubit,
       _crypto = crypto ?? CryptoRepository();

  void clear() => _rings.clear();

  /// [serverId] is the server the report was made on, or null for the
  /// selected one.
  Future<({ReportedContent content, ChatMessage? message})> open(
    MemberReport report, {
    String? serverId,
  }) async {
    final reported = report.message!;
    final authorName =
        report.target?.displayName ?? reported.originName ?? 'Unknown';

    ChatMessage messageOf(MessageBody body) => ChatMessage(
      id: '${reported.id}',
      authorId: report.targetId ?? '',
      authorName: authorName,
      authorAvatarPath: report.target?.avatarPath,
      text: body.text,
      attachments: body.attachments,
      sentAt: reported.createdAt,
      isMine: false,
    );

    if (reported.keyVersion == 0) {
      return (
        content: ReportedContent.plain,
        message: messageOf(MessageBody.decode(reported.ciphertext)),
      );
    }

    final ring = _rings[reported.channelId] ??= ChannelKeyring(
      serverCubit: _serverCubit,
      session: _session,
      vaultCubit: _vaultCubit,
      crypto: _crypto,
    );
    if (!ring.keys.containsKey(reported.keyVersion)) {
      await ring.absorbNewVersions(reported.channelId, serverId: serverId);
    }
    final key = ring.keys[reported.keyVersion];
    if (key == null) return (content: ReportedContent.locked, message: null);

    final signingKey = report.target?.publicKey;
    if (signingKey == null) {
      return (content: ReportedContent.unverified, message: null);
    }
    try {
      final plaintext = await _crypto.openMessage(
        envelope: MessageEnvelope(
          ciphertext: reported.ciphertext,
          nonce: reported.nonce ?? '',
          signature: reported.signature ?? '',
          keyVersion: reported.keyVersion,
        ),
        messageKey: key,
        senderPublicKey: CryptoRepository.fromBase64(signingKey),
        contextId: reported.channelId,
      );
      if (plaintext == null) {
        return (content: ReportedContent.unverified, message: null);
      }
      return (
        content: ReportedContent.verified,
        message: messageOf(MessageBody.decode(plaintext)),
      );
    } catch (e) {
      HelperMethods.printDebug('[Reports] could not open ${reported.id}: $e');
      return (content: ReportedContent.unverified, message: null);
    }
  }
}
