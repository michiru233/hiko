import '../models/album.dart';

final _rjPattern = RegExp(r'RJ\d{5,}', caseSensitive: false);
final _rjTitlePattern = RegExp(r'^RJ\d{5,}[_\- ]+(.+)$', caseSensitive: false);

/// 从多个候选中提取第一个 DLsite RJ 号（检查路径全层级，对应旧版 extractRjCode）
String? extractRjCode(Iterable<String?> values) {
  for (final v in values) {
    final match = _rjPattern.firstMatch(v ?? '');
    if (match != null) return match.group(0)!.toUpperCase();
  }
  return null;
}

/// 专辑兜底取 RJ 号（rjCode 缺失时从路径/标题/曲目名再提取，对应旧版 albumRjCode）
String? albumRjCode(Album album) {
  if (album.rjCode != null && album.rjCode!.isNotEmpty) return album.rjCode;
  final trackNames = album.tracks.map((t) => t.name).join(' ');
  return extractRjCode([album.sourcePath, album.title, trackNames]);
}

/// 文件夹名回退时清理：剥离 DLsite 的 "RJxxxxxx_" 前缀，只留作品名。
/// 例：RJ123456_雨夜耳语 → 雨夜耳语；无前缀则原样返回。
String? cleanFolderTitle(String? name) {
  if (name == null || name.trim().isEmpty) return name;
  final match = _rjTitlePattern.firstMatch(name.trim());
  final clean = match?.group(1)?.trim();
  return (clean == null || clean.isEmpty) ? name : clean;
}
