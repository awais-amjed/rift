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
/// static (`ARCHITECTURE.md` §5, *Receiving a call's audio*).
bool hearsRemoteAudio({
  required bool deafened,
  required bool stream,
  required bool watched,
  required bool ownerless,
}) {
  if (deafened || ownerless) return false;
  return !stream || watched;
}
