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

/// 日期时间展示：2026-10-31 20:48（历史快照等「某次操作的时刻」用）
String formatTimestamp(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// 文件大小展示：512 B / 4.2 KB / 9.5 MB（历史快照列表用）
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
