import 'package:intl/intl.dart';

import 'clock_time.dart';

/// When a conversation last moved, as its row in a list says it.
///
/// Today is a clock time, because that is how you remember today. Earlier this
/// week is the weekday, then a date, and a year only once it is a different
/// one — each as short as it can be while still telling rows apart, since it
/// shares the row with a name, a preview and a count.
String formatConversationTime(DateTime sentAt, DateTime now) {
  final local = sentAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return formatClock(local);
  if (days < 7) return DateFormat('EEE').format(local);
  if (local.year == now.year) return DateFormat('MMM d').format(local);
  return DateFormat('MMM d, y').format(local);
}

/// When one message was sent, as a list of single messages says it — the
/// pinned list, where each row stands alone rather than under a day divider.
///
/// Today and yesterday keep the clock time, because that is what tells two
/// pins from the same day apart. Anything older is the date, with a year only
/// once it is a different one.
String formatMessageMoment(DateTime sentAt, DateTime now) {
  final local = sentAt.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  final clock = formatClock(local);
  if (days <= 0) return 'Today at $clock';
  if (days == 1) return 'Yesterday at $clock';
  if (local.year == now.year) return DateFormat('MMM d').format(local);
  return DateFormat('MMM d, y').format(local);
}
