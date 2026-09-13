/// 声优/社团人名拆分（1.77 移动端详情页同款分隔符语义，1.81 抽出共享供抽屉胶囊用）。
library;

/// 声优串分隔符：顿号/逗号/斜杠/分号（中日输入习惯全覆盖）
final voiceSplitPattern = RegExp(r'[、，,／/;；]');

/// 把声优串拆成逐人名单（去空白、滤空项）；社团名不做拆分（社团是单值）。
List<String> splitVoiceNames(String artist) => artist
    .split(voiceSplitPattern)
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();
