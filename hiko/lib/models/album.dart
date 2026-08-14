import 'track.dart';

/// 专辑（作品）数据模型，字段对齐旧版 library.json 已验证 schema
class Album {
  final String id; // local-<sha1(sourcePath) 前 16 位>
  final String sourcePath; // 桌面：绝对路径；Android：content:// 目录 URI
  String title;
  String artist;
  String albumArtist;
  String? rjCode;
  String? dlsiteTitle;
  List<String> tags;
  String group;
  String genre; // 未分类 / ASMR / 剧情向 / 治愈系 / 环境音
  int duration; // 曲目数量
  double totalDuration; // 秒
  double played; // 已播放进度（秒）
  bool favorite;
  DateTime date; // 添加时间
  List<Track> tracks;
  String? localCover; // dataURL / file:// / content://
  String? currentCover; // 运行时字段：当前轨内嵌封面
  List<String> color; // [c1, c2] 渐变兜底封面
  String shape; // 12 种之一

  Album({
    required this.id,
    required this.sourcePath,
    required this.title,
    this.artist = '本地导入',
    this.albumArtist = '',
    this.rjCode,
    this.dlsiteTitle,
    this.tags = const [],
    this.group = '本地文件夹',
    this.genre = '未分类',
    this.duration = 0,
    this.totalDuration = 0,
    this.played = 0,
    this.favorite = false,
    required this.date,
    this.tracks = const [],
    this.localCover,
    this.currentCover,
    this.color = const ['#c4b8e8', '#4b416c'],
    this.shape = 'radio',
  });

  factory Album.fromJson(Map<String, dynamic> json) => Album(
        id: json['id'] as String? ?? '',
        sourcePath: json['sourcePath'] as String? ?? '',
        title: json['title'] as String? ?? '未命名',
        artist: json['artist'] as String? ?? '本地导入',
        albumArtist: json['albumArtist'] as String? ?? '',
        rjCode: json['rjCode'] as String?,
        dlsiteTitle: json['dlsiteTitle'] as String?,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
        group: json['group'] as String? ?? '本地文件夹',
        genre: json['genre'] as String? ?? '未分类',
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        totalDuration: (json['totalDuration'] as num?)?.toDouble() ?? 0,
        played: (json['played'] as num?)?.toDouble() ?? 0,
        favorite: json['favorite'] as bool? ?? false,
        date: DateTime.fromMillisecondsSinceEpoch(
            (json['date'] as num?)?.toInt() ?? 0),
        tracks: (json['tracks'] as List?)
                ?.map((t) => Track.fromJson(Map<String, dynamic>.from(t as Map)))
                .toList() ??
            const [],
        localCover: json['localCover'] as String?,
        color: (json['color'] as List?)?.cast<String>() ??
            const ['#c4b8e8', '#4b416c'],
        shape: json['shape'] as String? ?? 'radio',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourcePath': sourcePath,
        'title': title,
        'artist': artist,
        'albumArtist': albumArtist,
        if (rjCode != null) 'rjCode': rjCode,
        if (dlsiteTitle != null) 'dlsiteTitle': dlsiteTitle,
        if (tags.isNotEmpty) 'tags': tags,
        'group': group,
        'genre': genre,
        'duration': duration,
        'totalDuration': totalDuration,
        'played': played,
        'favorite': favorite,
        'date': date.millisecondsSinceEpoch,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        if (localCover != null) 'localCover': localCover,
        'color': color,
        'shape': shape,
      };

  Album copyWith({
    String? title,
    String? artist,
    String? albumArtist,
    String? rjCode,
    String? dlsiteTitle,
    List<String>? tags,
    String? genre,
    double? played,
    bool? favorite,
    List<Track>? tracks,
    String? localCover,
    String? currentCover,
  }) =>
      Album(
        id: id,
        sourcePath: sourcePath,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        albumArtist: albumArtist ?? this.albumArtist,
        rjCode: rjCode ?? this.rjCode,
        dlsiteTitle: dlsiteTitle ?? this.dlsiteTitle,
        tags: tags ?? this.tags,
        group: group,
        genre: genre ?? this.genre,
        duration: (tracks ?? this.tracks).length,
        totalDuration: (tracks ?? this.tracks)
            .fold<double>(0, (sum, t) => sum + t.duration),
        played: played ?? this.played,
        favorite: favorite ?? this.favorite,
        date: date,
        tracks: tracks ?? this.tracks,
        localCover: localCover ?? this.localCover,
        currentCover: currentCover ?? this.currentCover,
        color: color,
        shape: shape,
      );

  /// 是否关联本地文件（桌面 file:// 或 Android content://）
  bool get hasLocalFiles =>
      sourcePath.isNotEmpty ||
      tracks.any((t) => t.url.startsWith('file:') || t.url.startsWith('content:'));
}
