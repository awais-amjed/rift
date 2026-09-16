/// Someone who could hand this member a channel's key, and whether they are
/// here to do it.
class KeyHolder {
  final String id;
  final String name;
  final bool online;

  const KeyHolder({required this.id, required this.name, required this.online});
}

/// Who can hand over a channel key, in the order worth reading them.
///
/// A key is wrapped for a new member by somebody who already holds it, and only
/// while that somebody's client is running — so the one useful fact on a
/// "waiting for the key" screen is who those people are and whether any of
/// them is online. Online first, since they are the ones it is waiting on;
/// then by name, so the list doesn't shuffle as people come and go within a
/// group. The member waiting is never on their own list.
List<KeyHolder> orderKeyHolders({
  required Map<String, String> names,
  required Set<String> onlineIds,
  required String? me,
}) {
  final holders = [
    for (final entry in names.entries)
      if (entry.key != me)
        KeyHolder(
          id: entry.key,
          name: entry.value,
          online: onlineIds.contains(entry.key),
        ),
  ];
  holders.sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return holders;
}
