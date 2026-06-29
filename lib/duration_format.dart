String formatDurationLabel(int totalMinutes) {
  if (totalMinutes < 60) {
    return '$totalMinutes min';
  }

  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0) {
    return '${hours}h';
  }

  return '${hours}h ${minutes}m';
}
