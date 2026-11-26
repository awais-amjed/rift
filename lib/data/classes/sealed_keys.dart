import 'package:equatable/equatable.dart';

/// One channel's batch of sealed keys, as the server stores it: a key
/// version sealed to each member in [entries], and when [mint], the version
/// before sealed under it ([link]).
///
/// A sweep pass is a list of these sent at once (`store_key_work`), so a
/// newcomer's keys for every channel they see land in one request.
class SealedKeys extends Equatable {
  final String channelId;
  final int keyVersion;

  /// `{user_id, ephemeral_public_key, ciphertext, nonce}` each, from
  /// `CryptoRepository.sealKeyringEntries`.
  final List<Map<String, dynamic>> entries;

  /// A new version, which only one writer can win; otherwise a heal of one
  /// that exists, which skips anybody sealed meanwhile.
  final bool mint;

  final ({String ciphertext, String nonce})? link;

  const SealedKeys({
    required this.channelId,
    required this.keyVersion,
    required this.entries,
    required this.mint,
    this.link,
  });

  /// The body `post_channel_keys` takes, and one job of `store_key_work`.
  Map<String, dynamic> toJson() => {
    'channel_id': channelId,
    'key_version': keyVersion,
    'entries': entries,
    'mint': mint,
    if (link != null)
      'link': {'ciphertext': link!.ciphertext, 'nonce': link!.nonce},
  };

  @override
  List<Object?> get props => [channelId, keyVersion, entries, mint, link];
}
