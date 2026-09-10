/// 歌词 sidecar 扩展名（.lrc/.vtt/.srt）
const lyricExtensions = {'.lrc', '.vtt', '.srt'};

/// [lyricName] 是否为音频 [audioName] 的 sidecar 歌词（大小写不敏感）。
///
/// 两种命名约定都要认：
/// - 同名换扩展名：`01.mp3` → `01.lrc`
/// - 完整音频名加后缀：`track01 柊莉花.mp3` → `track01 柊莉花.mp3.vtt`（DLsite 常见）
///
/// 只按「去扩展名后相等」比对会把第二种判为不匹配（歌词侧多留一个 `.mp3`），
/// 安卓端这类歌词曾整片丢失。
bool isLyricFor(String audioName, String lyricName) {
  final lyricDot = lyricName.lastIndexOf('.');
  if (lyricDot <= 0) return false;
  if (!lyricExtensions.contains(lyricName.substring(lyricDot).toLowerCase())) {
    return false;
  }

  final base = lyricName.substring(0, lyricDot).toLowerCase();
  final audioDot = audioName.lastIndexOf('.');
  final audio = audioName.toLowerCase();
  return base == audio ||
      base == (audioDot <= 0 ? audio : audio.substring(0, audioDot));
}
