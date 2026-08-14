/// 时间格式化（对应旧版 app.js formatTime / formatDuration）
String formatTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '00:00';
  final min = seconds ~/ 60;
  final sec = (seconds % 60).floor().toString().padLeft(2, '0');
  return '$min:$sec';
}

/// 时长展示：1小时23分钟 / 2小时 / 45分钟 / --
String formatDuration(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return '--';
  final totalMin = (seconds / 60).round();
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h > 0 && m > 0) return '$h小时$m分钟';
  if (h > 0) return '$h小时';
  return '$m分钟';
}
