const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

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

String chatListTimeLabel(
  DateTime at, {
  required DateTime now,
  required bool use24Hour,
}) {
  final local = at.toLocal();
  final today = DateTime.utc(now.year, now.month, now.day);
  final day = DateTime.utc(local.year, local.month, local.day);
  final daysAgo = today.difference(day).inDays;

  if (daysAgo <= 0) return clockLabel(local, use24Hour);
  if (daysAgo == 1) return 'Yesterday';
  if (daysAgo < 7) return _weekdays[local.weekday - 1];
  final dayMonth = '${local.day} ${_months[local.month - 1]}';
  return local.year == now.year ? dayMonth : '$dayMonth ${local.year}';
}

String clockLabel(DateTime time, bool use24Hour) {
  final minute = time.minute.toString().padLeft(2, '0');
  if (use24Hour) return '${time.hour.toString().padLeft(2, '0')}:$minute';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
}
