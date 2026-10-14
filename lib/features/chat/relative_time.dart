/// "5m ago" and friends, for the conversation list.
library;

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// How long before [now] [time] was, in the fewest words that still order a
/// list. A time ahead of [now] — clock skew between phone and server — reads
/// as "just now".
String relativeTime(DateTime time, DateTime now) {
  final age = now.difference(time);
  if (age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${age.inMinutes}m ago';
  if (age.inDays < 1) return '${age.inHours}h ago';
  if (age.inDays < 7) return '${age.inDays}d ago';
  final date = '${time.day} ${_months[time.month - 1]}';
  return time.year == now.year ? date : '$date ${time.year}';
}

/// How long until [time], for "resets in 2h 36m". A moment already past, or
/// less than a minute away, reads as "now".
String timeUntil(DateTime time, DateTime now) {
  final left = time.difference(now);
  if (left.inMinutes < 1) return 'now';
  if (left.inHours < 1) return 'in ${left.inMinutes}m';
  if (left.inDays < 1) return 'in ${left.inHours}h ${left.inMinutes % 60}m';
  return 'in ${left.inDays}d ${left.inHours % 24}h';
}
