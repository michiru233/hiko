/// 音轨数据模型（对应旧版 library.json 的 tracks 元素）
class Track {
  final int index;
  String name;
  final String url;
  double duration; // 秒
  String? cover; // 内嵌封面 dataURL（可空）
  String? lyricsText; // 同名歌词全文（.lrc/.vtt/.srt，Android SAF 导入时随事件回传；旧库无此字段为 null）

  Track({
    required this.index,
    required this.name,
    required this.url,
    this.duration = 0,
    this.cover,
    this.lyricsText,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        index: (json['index'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        cover: json['cover'] as String?,
        lyricsText: json['lyricsText'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'url': url,
        'duration': duration,
        if (cover != null) 'cover': cover,
        if (lyricsText != null) 'lyricsText': lyricsText,
      };

  Track copyWith(
          {String? name, double? duration, String? cover, String? lyricsText}) =>
      Track(
        index: index,
        name: name ?? this.name,
        url: url,
        duration: duration ?? this.duration,
        cover: cover ?? this.cover,
        lyricsText: lyricsText ?? this.lyricsText,
      );
}
