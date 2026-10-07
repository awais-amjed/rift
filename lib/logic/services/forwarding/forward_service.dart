import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/attachment.dart';
import '../../../data/classes/forwarded_message.dart';
import '../../../data/classes/message_body.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../data/classes/server.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../../../data/repositories/central_dm_repository.dart';
import '../../../supabase_config.dart';
import '../../cubits/server/server_cubit.dart';
import '../../cubits/vault/vault_cubit.dart';
import '../../helper_methods.dart';
import '../attachment_staging.dart';
import '../file_save/save_target.dart';
import 'forward_target.dart';

part 'forward_service_blobs.dart';
part 'forward_service_dms.dart';

/// What came back from forwarding one message to one place.
class ForwardResult {
  final ForwardTarget target;
  final String? error;

  const ForwardResult(this.target, {this.error});

  bool get sent => error == null;
}

/// Over the helper budget and one job: forwarding a message. Blobs and DMs are
/// already parts.
///
/// Carrying a message into other conversations.
///
/// **A forward is a new message, not a moved one**, and this is the whole
/// reason the class exists rather than a parameter on a send: the readers at
/// the destination hold no key to the room it came from, so the content is
/// re-sealed under *their* key and signed by the forwarder. Nothing of the
/// original's cryptography survives the trip, which is why the block it
/// arrives in is labelled a claim (see [ForwardedMessage]).
///
/// Built at the call site from the cubits already in scope rather than
/// provided app-wide: it owns no state, it is used by one dialog, and the
/// alternative is a fourth chat cubit that only ever writes.
class ForwardService with _ForwardBlobsMixin, _ForwardDmsMixin {
  @override
  final ServerCubit servers;
  @override
  final VaultCubit vault;
  @override
  final CryptoRepository crypto;
  @override
  final CentralDmRepository central;

  ForwardService({
    required this.servers,
    required this.vault,
    required this.crypto,
    CentralDmRepository? central,
  }) : central = central ?? CentralDmRepository();

  /// Forward [message] to each of [targets], with an optional [note] of the
  /// forwarder's own.
  ///
  /// One result per target, in order, because the destinations fail
  /// independently: a server that is down must not take the other four with
  /// it, and "sent to three of five" is a thing the caller has to be able to
  /// say. The blobs are fetched **once** and re-uploaded per destination —
  /// each server keeps its own bucket, and a path into somebody else's is a
  /// link their members cannot open.
  Future<List<ForwardResult>> forward({
    required ForwardedMessage message,
    required List<ForwardTarget> targets,
    String? sourceServerId,
    String? note,
  }) async {
    final fetched = await _fetchBlobs(message.attachments, sourceServerId);

    final results = <ForwardResult>[];
    try {
      for (final target in targets) {
        try {
          final error = await _sendOne(target, message, fetched.files, note);
          results.add(ForwardResult(target, error: error));
        } catch (e) {
          HelperMethods.printDebug('[Forward] ${target.id} failed: $e');
          results.add(ForwardResult(target, error: 'Could not forward'));
        }
      }
    } finally {
      for (final scratch in fetched.scratch) {
        await scratch.discard();
      }
    }
    return results;
  }

  /// Null on success, a sentence otherwise.
  Future<String?> _sendOne(
    ForwardTarget target,
    ForwardedMessage message,
    List<PendingAttachment?> files,
    String? note,
  ) => switch (target) {
    ChannelTarget() => _sendToChannel(target, message, files, note),
    ServerDmTarget() => _sendToServerDm(target, message, files, note),
    CentralDmTarget() => _sendToCentralDm(target, message, files, note),
  };

  // ── Channels ──────────────────────────────────────────────

  Future<String?> _sendToChannel(
    ChannelTarget target,
    ForwardedMessage message,
    List<PendingAttachment?> files,
    String? note,
  ) async {
    final server = target.server;
    // Forwarded into a channel whose encryption is off, it goes the way
    // everything else there does: in the clear, files too, and signed.
    final plain = !target.channel.isEncrypted;
    final key = plain ? null : await _channelKey(server, target.channel.id);
    if (key == null && !plain) {
      // Deliberately not bootstrapped from here. Minting a channel's first
      // key is a decision with a race in it (`ChannelKeyring._bootstrap`),
      // and doing it silently from a forward would mean the first key a
      // channel ever had was created by somebody who never opened it.
      return 'No key for #${target.channel.name} yet — open it once first.';
    }

    final attachments = await _reupload(
      message.attachments,
      files,
      scopePrefix: target.channel.id,
      serverId: server.id,
      plain: plain,
    );
    final identity = await _identityFor(server);
    if (identity == null) return 'Your vault is locked.';

    final body = MessageBody(
      text: note ?? '',
      forwarded: message.withAttachments(attachments),
    ).encode();
    final envelope = key == null
        ? await crypto.signPlaintext(
            plaintext: body,
            signingKeyPair: identity.keyPair,
            contextId: target.channel.id,
          )
        : await crypto.sealMessage(
            plaintext: body,
            messageKey: key.bytes,
            signingKeyPair: identity.keyPair,
            contextId: target.channel.id,
            keyVersion: key.version,
          );

    final response = await servers.sendChatMessage(
      channelId: target.channel.id,
      envelope: envelope.toJson(),
      serverId: server.id,
    );
    return response.success ? null : (response.error?.toString() ?? 'Failed');
  }

  /// The newest channel key this member already holds, or null.
  ///
  /// A read, never a write: no bootstrap, no healing of other members. Both
  /// belong to opening a channel, where somebody is waiting and can be told
  /// what happened — `ChannelKeyring` does them and is the only thing that
  /// should.
  Future<({Uint8List bytes, int version})?> _channelKey(
    Server server,
    String channelId,
  ) async {
    final identity = await _chatIdentityFor(server);
    if (identity == null) return null;

    final response = await servers.getChannelKey(
      channelId,
      serverId: server.id,
    );
    if (!response.success) return null;

    final data = response.data as Map<String, dynamic>;
    final version = data['current_version'] as int? ?? 0;
    if (version == 0) return null;

    for (final entry
        in (data['my_keys'] as List? ?? const [])
            .cast<Map<String, dynamic>>()) {
      if (entry['key_version'] != version) continue;
      try {
        final bytes = await crypto.unwrapKey(
          wrapped: WrappedKey.fromJson(entry),
          myKeyPair: identity.keyPair,
        );
        return (bytes: bytes, version: version);
      } catch (e) {
        HelperMethods.printDebug('[Forward] unwrap failed: $e');
        return null;
      }
    }
    return null;
  }

  // ── Identities ────────────────────────────────────────────

  @override
  Future<ServerIdentity?> _identityFor(Server server) async {
    if (vault.state.masterSeed == null) return null;
    return vault.getIdentityForHost(
      Uri.parse(server.supabaseUrl).host,
      serverId: server.id,
      version: server.keyVersion,
    );
  }

  Future<ChatIdentity?> _chatIdentityFor(Server server) async {
    if (vault.state.masterSeed == null) return null;
    return vault.getChatIdentityForHost(Uri.parse(server.supabaseUrl).host);
  }
}
