import 'package:intl/intl.dart';

/// When a time-out ends, said the way a person would check it: the time alone
/// today, the weekday within a week, the date after that.
///
/// Pure, with [now] passable, so the three shapes are testable.
String timeOutEndLabel(DateTime until, {DateTime? now}) {
  final local = until.toLocal();
  final today = now ?? DateTime.now();
  final clock = DateFormat('HH:mm').format(local);
  final startOfToday = DateTime(today.year, today.month, today.day);
  final days = DateTime(
    local.year,
    local.month,
    local.day,
  ).difference(startOfToday).inDays;
  if (days <= 0) return clock;
  if (days == 1) return 'tomorrow $clock';
  if (days < 7) return '${DateFormat('EEEE').format(local)} $clock';
  return '${DateFormat('MMM d').format(local)}, $clock';
}
