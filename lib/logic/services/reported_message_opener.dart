import 'package:rift_crypto/rift_crypto.dart';

import '../../data/classes/chat_message.dart';
import '../../data/classes/member_report.dart';
import '../../data/classes/message_body.dart';
import '../../data/classes/poll.dart';
import '../../data/repositories/session_repository.dart';
import '../cubits/vault/vault_cubit.dart';
import '../helper_methods.dart';
import 'channel_keyring.dart';
import 'sealed_open.dart';

/// What a reviewer's device made of a reported message.
enum ReportedContent {
  /// Opened with the channel key and signed by the member it names.
  verified,

  /// A webhook's, sent in the clear and signed by nobody, since GitHub holds
  /// no Rift key. Safe to show because no person's name is put behind it.
  plain,

  /// Sent in the clear by a member — a command, or a channel with encryption
  /// off — and checked against their signature like a sealed one.
  signedPlain,

  /// Sealed under a key this device does not hold: a private channel the
  /// reviewer is not inside, or a key nobody has wrapped for them yet.
  locked,

  /// The signature does not match. Not shown — the same rule as a forged
  /// message anywhere (ARCHITECTURE.md §4) — only said.
  unverified,
}

/// A reported message as opened: what it came to, the message when it could
/// be read, and its poll's question and options (a poll's rules and tally are
/// not on the report, so it is drawn as words, not as a poll).
typedef OpenedReport = ({
  ReportedContent content,
  ChatMessage? message,
  PollBody? poll,
});

/// Opens the sealed envelope a message report kept, with the reviewer's own
/// channel keys, and checks the author's signature.
///
/// The keys come from the same keyring a channel opens with, read-only: this
/// never bootstraps a key or heals anybody, because reading a report is not
/// joining the channel. One ring per channel, kept for as long as the reports
/// page lives, so a page of reports from one channel fetches its keys once.
class ReportedMessageOpener {
  final SessionRepository _session;
  final VaultCubit _vaultCubit;
  final CryptoRepository _crypto;
  final Map<String, ChannelKeyring> _rings = {};

  /// Channels already asked for a key in this read of the list and found
  /// without it, so ten reports from a channel the reviewer is not in ask
  /// once, not ten times. Forgotten at the next read ([newRead]), when a key
  /// may have been wrapped for them since.
  final Set<String> _missed = {};

  ReportedMessageOpener({
    required SessionRepository session,
    required VaultCubit vaultCubit,
    CryptoRepository? crypto,
  }) : _session = session,
       _vaultCubit = vaultCubit,
       _crypto = crypto ?? CryptoRepository();

  void clear() {
    _rings.clear();
    _missed.clear();
  }

  /// A new read of the reports list is starting.
  void newRead() => _missed.clear();

  /// [serverId] is the server the report was made on.
  Future<OpenedReport> open(
    MemberReport report, {
    required String serverId,
  }) async {
    final reported = report.message!;
    final authorName =
        report.target?.displayName ?? reported.originName ?? 'Unknown';

    OpenedReport opened(ReportedContent content, String plaintext) {
      final body = MessageBody.decode(plaintext);
      return (
        content: content,
        message: ChatMessage(
          id: '${reported.id}',
          authorId: report.targetId ?? '',
          authorName: authorName,
          authorAvatarPath: report.target?.avatarPath,
          text: body.text,
          attachments: body.attachments,
          preview: body.preview,
          forwarded: body.forwarded,
          sentAt: reported.createdAt,
          isMine: false,
        ),
        poll: body.poll,
      );
    }

    const OpenedReport locked = (
      content: ReportedContent.locked,
      message: null,
      poll: null,
    );
    const OpenedReport unverified = (
      content: ReportedContent.unverified,
      message: null,
      poll: null,
    );
    final envelope = MessageEnvelope(
      ciphertext: reported.ciphertext,
      nonce: reported.nonce ?? '',
      signature: reported.signature ?? '',
      keyVersion: reported.keyVersion,
    );
    final signingKey = report.target?.publicKey;

    if (reported.keyVersion == 0) {
      // A webhook's is nobody's, so there is nothing to check. A member's is
      // put under their name, so it is checked exactly as the chat checks it
      // (`PlainRows.open`): readable is not a reason to believe whose it is.
      if (report.targetId == null && reported.originName != null) {
        return opened(ReportedContent.plain, reported.ciphertext);
      }
      if (signingKey == null) return unverified;
      final verified = await _crypto.verifyPlaintext(
        envelope: envelope,
        senderPublicKey: CryptoRepository.fromBase64(signingKey),
        contextId: reported.channelId,
      );
      return verified
          ? opened(ReportedContent.signedPlain, reported.ciphertext)
          : unverified;
    }

    final ring = _rings[reported.channelId] ??= ChannelKeyring(
      session: _session,
      vaultCubit: _vaultCubit,
      crypto: _crypto,
    );
    final asked = '${reported.channelId}:${reported.keyVersion}';
    if (!ring.keys.containsKey(reported.keyVersion) &&
        !_missed.contains(asked)) {
      await ring.absorbNewVersions(reported.channelId, serverId: serverId);
    }
    final key = ring.keys[reported.keyVersion];
    if (key == null) {
      _missed.add(asked);
      return locked;
    }
    if (signingKey == null) return unverified;

    // A signature that holds over a body this device's key will not open is
    // the key's fault, not a forgery: locked, as in the chat (`openSealed`).
    try {
      final result = await openSealed(
        _crypto,
        envelope: envelope,
        messageKey: key,
        senderPublicKey: CryptoRepository.fromBase64(signingKey),
        contextId: reported.channelId,
      );
      return switch (result.outcome) {
        SealedOutcome.opened => opened(
          ReportedContent.verified,
          result.plaintext!,
        ),
        SealedOutcome.locked => locked,
        SealedOutcome.dropped => unverified,
      };
    } catch (e) {
      HelperMethods.printDebug('[Reports] could not open ${reported.id}: $e');
      return unverified;
    }
  }
}
