/// Whether this client should hear a remote audio track.
///
/// Deafened, nothing. A stream's sound only while the stream is watched — a
/// sound share is heard like a person, so it is not a [stream] here — and a
/// share whose owner has left the call ([ownerless], see
/// `sharesWithoutOwner`) not at all.
///
/// What is not heard is *disabled* (`LiveKitCubit._syncAudioReception`),
/// never unsubscribed: an unsubscribed track's slot on the connection is
/// handed to the next track to arrive, and subscribing to the first again
/// opens a second slot under the same id, which is how a call turned to
/// static (`CALLS.md`, *Receiving a call's audio*).
bool hearsRemoteAudio({
  required bool deafened,
  required bool stream,
  required bool watched,
  required bool ownerless,
}) {
  if (deafened || ownerless) return false;
  return !stream || watched;
}

/// The ids carried by more than one of [receiverIds] — receivers of one
/// connection that each hold a live track.
///
/// A connection's receivers should never share one, but the call can still
/// arrive at it from outside: a slot keeps the id of the track it was made
/// for, so a track subscribed again — by the server, for a member who hid
/// their voice and showed it again — gets a second slot under the same id,
/// and flutter_webrtc puts its frame cryptor on whichever comes first.
Set<String> sharedReceiverIds(Iterable<String> receiverIds) {
  final seen = <String>{};
  return {
    for (final id in receiverIds)
      if (!seen.add(id)) id,
  };
}
