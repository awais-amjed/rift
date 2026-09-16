import 'package:intl/intl.dart';

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
  if (days <= 0) return DateFormat('HH:mm').format(local);
  if (days < 7) return DateFormat('EEE').format(local);
  if (local.year == now.year) return DateFormat('MMM d').format(local);
  return DateFormat('MMM d, y').format(local);
}
