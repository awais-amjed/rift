/// Which watched stream floats over a chat while the call is out of sight
/// (`CallStreamPip`).
///
/// The one last opened full size on the stage, since that is the one the
/// user was looking at; with two watched, the one started last could be the
/// one they had just put to the side. Once that stream is no longer watched,
/// or none has been opened, it is the one watched last: [watching] keeps the
/// order streams were added in.
String? callPipStream(Set<String> watching, {required String? lookedAt}) =>
    lookedAt != null && watching.contains(lookedAt)
    ? lookedAt
    : watching.lastOrNull;
