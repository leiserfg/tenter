String formatDuration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String formatPreciseDuration(int milliseconds) {
  final value = milliseconds.clamp(0, 1 << 62).toInt();
  final minutes = value ~/ 60000;
  final seconds = (value ~/ 1000) % 60;
  final millis = value % 1000;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(3, '0')}';
}

String formatDate(DateTime date) {
  final now = DateTime.now();
  final sameDay =
      now.year == date.year && now.month == date.month && now.day == date.day;
  if (sameDay) {
    return 'TODAY ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
