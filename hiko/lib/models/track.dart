/// 音轨数据模型（对应旧版 library.json 的 tracks 元素）
class Track {
  final int index;
  String name;
  final String url;
  double duration; // 秒
  String? cover; // 内嵌封面 dataURL（可空）

  Track({
    required this.index,
    required this.name,
    required this.url,
    this.duration = 0,
    this.cover,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        index: (json['index'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        cover: json['cover'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'name': name,
        'url': url,
        'duration': duration,
        if (cover != null) 'cover': cover,
      };

  Track copyWith({String? name, double? duration}) => Track(
        index: index,
        name: name ?? this.name,
        url: url,
        duration: duration ?? this.duration,
        cover: cover,
      );
}
