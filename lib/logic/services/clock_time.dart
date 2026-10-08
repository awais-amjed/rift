import 'package:intl/intl.dart';

/// A time of day as Rift shows it: twelve-hour, with AM or PM ("9:05 PM").
///
/// Every timestamp goes through here, so a message, a call and a time-out
/// never disagree about how a time reads.
String formatClock(DateTime local) => DateFormat('h:mm a').format(local);
