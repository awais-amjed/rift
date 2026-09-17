/// What a shared track's tile is called.
///
/// "RotB's sound" said the least useful half of it. What a room wants to know
/// is *what is playing* — the application is the closest thing to that which
/// is knowable from outside it, and it travels as the published track's name.
///
/// [app] is that name, absent or empty when the application did not give one
/// (and always, for a share published by an older client). The fallback still
/// has to name the owner: several people can be sharing at once, so a tile
/// that only said "Audio" would leave you turning the wrong one down.
String soundShareLabel({
  required String owner,
  required String? app,
  required bool isOwn,
}) {
  final name = app?.trim() ?? '';
  final who = isOwn ? 'You' : owner.trim();
  if (name.isEmpty) return isOwn ? 'Your audio' : '$who’s audio';
  if (who.isEmpty) return name;
  return '$who · $name';
}
