/// 在线音声作品模型（Kikoeru 兼容服务器 / asmr.one）。
///
/// 与本地 `Album` 完全独立：在线数据不写入 `library.json`，只活在内存里，
/// 避免污染本地库去重、清理与统计逻辑（见 data/online/online_provider.dart）。
library;

import 'package:flutter/foundation.dart' show immutable;

/// 在线作品（`GET /api/works` 列表项 / `GET /api/work/{id}?v=2` 详情）。
///
/// **1.94.0 纠正一处误判**：1.90 起这里写着「列表接口不返回 tags / vas，
/// 所以列表态下这两项为空」—— 实测是错的。`/api/works`、`POST /api/search/{kw}`、
/// `/api/tags/{id}/works` 的列表项**都带完整的 `tags` / `vas`**
/// （`vas` 实测形如 `{id, name}`，`tags` 形如 `{id, name, i18n}`），
/// 且与详情接口逐条比对 `id` + `name` **完全一致**。
///
/// 这个误判的代价是 [tags] 一度只留名字、丢掉 `id` —— 而按标签筛选要的正是 `id`。
/// 现在 [tags] 保留完整对象，卡片上点标签可以直接发请求，不需要反查标签表。
class OnlineWork {
  const OnlineWork({
    required this.id,
    required this.title,
    this.circleId,
    this.circleName = '',
    this.release,
    this.createDate,
    this.dlCount = 0,
    this.rateCount = 0,
    this.rateAverage = 0,
    this.hasSubtitle = false,
    this.durationSeconds = 0,
    this.tags = const [],
    this.vas = const [],
    this.rjCode,
    this.nsfw = false,
  });

  final int id;
  final String title;
  final int? circleId;
  final String circleName;
  final DateTime? release;
  final DateTime? createDate;
  final int dlCount;
  final int rateCount;
  final double rateAverage;
  final bool hasSubtitle;

  /// 作品总时长（秒），服务端字段 `duration`
  final int durationSeconds;

  /// 标签（带 `id`，可直接用于 `/api/tags/{id}/works`）。
  /// `id <= 0` 表示服务端只给了名字（异常形态），此时标签只展示、不可点。
  final List<OnlineTag> tags;
  final List<String> vas;

  /// DLsite 作品号，服务端字段 `source_id`（如 `RJ01657200`）
  final String? rjCode;
  final bool nsfw;

  /// 在线专辑 id 约定：`online-<workId>`。
  ///
  /// 本地专辑是 `local-<sha1 前 16 位>`。前缀既用于区分来源，
  /// 也用于让播放控制器判断「当前队列是本地库还是在线列表」。
  static String albumIdFor(int workId) => 'online-$workId';

  /// 在线来源的 sourcePath 约定（不可解析为真实路径，仅供来源判定与展示）
  static String sourcePathFor(int workId) => 'online://$workId';

  String get albumId => albumIdFor(id);

  /// 形如 `1:23:45` / `12:34`；0 秒返回空串（UI 自行决定是否隐藏）
  String get durationLabel {
    if (durationSeconds <= 0) return '';
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
    return h > 0
        ? '$h:$mm:${s.toString().padLeft(2, '0')}'
        : '$mm:${s.toString().padLeft(2, '0')}';
  }

  /// 作品网页地址（展示 / 「在浏览器打开」用，不参与下载）
  String? shareUrl(String serverBase) => onlineWorkPageUrl(serverBase, id);

  factory OnlineWork.fromJson(Map<String, dynamic> json) {
    return OnlineWork(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : '未命名作品',
      circleId: (json['circle_id'] as num?)?.toInt(),
      circleName: (json['name'] as String?) ?? '',
      release: _parseDate(json['release']),
      createDate: _parseDate(json['create_date']),
      dlCount: (json['dl_count'] as num?)?.toInt() ?? 0,
      rateCount: (json['rate_count'] as num?)?.toInt() ?? 0,
      rateAverage: (json['rate_average_2dp'] as num?)?.toDouble() ?? 0,
      hasSubtitle: json['has_subtitle'] as bool? ?? false,
      durationSeconds: (json['duration'] as num?)?.toInt() ?? 0,
      tags: parseOnlineTags(json['tags']),
      vas: parseVoiceActorNames(json['vas']),
      rjCode: _normalizeRj(json['source_id']),
      nsfw: json['nsfw'] as bool? ?? false,
    );
  }

  /// 浅拷贝用于详情补齐（详情接口返回的字段更全：tags/vas/封面等）。
  /// 列表态其实也带 tags/vas（见类注释），这里仍以详情为准做兜底合并。
  OnlineWork merged(OnlineWork detail) => OnlineWork(
        id: id,
        title: detail.title.isNotEmpty ? detail.title : title,
        circleId: detail.circleId ?? circleId,
        circleName: detail.circleName.isNotEmpty ? detail.circleName : circleName,
        release: detail.release ?? release,
        createDate: detail.createDate ?? createDate,
        dlCount: detail.dlCount,
        rateCount: detail.rateCount,
        rateAverage: detail.rateAverage,
        hasSubtitle: detail.hasSubtitle,
        durationSeconds: detail.durationSeconds > 0
            ? detail.durationSeconds
            : durationSeconds,
        tags: detail.tags.isNotEmpty ? detail.tags : tags,
        vas: detail.vas.isNotEmpty ? detail.vas : vas,
        rjCode: detail.rjCode ?? rjCode,
        nsfw: detail.nsfw,
      );

  static DateTime? _parseDate(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim());
  }

  /// `source_id` 统一成大写 `RJxxxxxxx` 形式；非 RJ 作品（如漫画）返回 null
  static String? _normalizeRj(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return null;
    final upper = raw.trim().toUpperCase();
    return RegExp(r'^RJ\d+$').hasMatch(upper) ? upper : null;
  }

  /// 标签解析：`[{id, name, i18n}]` 或纯字符串数组。
  ///
  /// 名字优先中文（`i18n.zh-cn`），回退服务端默认 `name` —— asmr.one 的标签体系自带
  /// 多语言，中文用户直接看中文比日文原文友好（实测服务端 `name` 本身也已是 zh-cn）。
  ///
  /// **保留 `id`**：按标签筛选走 `/api/tags/{id}/works`，名字在服务端不唯一、也不能当 key。
  /// 纯字符串形态（异常/测试用）给 `id = 0`，调用方据此把它当只读标签。
  static List<OnlineTag> parseOnlineTags(Object? raw) {
    if (raw is! List) return const [];
    final out = <OnlineTag>[];
    final seenIds = <int>{};
    final seenNames = <String>{};
    for (final item in raw) {
      final tag = switch (item) {
        String s => OnlineTag(id: 0, name: s.trim()),
        Map m => OnlineTag.fromJson(Map<String, dynamic>.from(m)),
        _ => null,
      };
      if (tag == null || tag.name.isEmpty) continue;
      // 有 id 按 id 去重（同一个标签可能重复出现）；没 id 只能按名字
      final dup = tag.id > 0 ? !seenIds.add(tag.id) : !seenNames.add(tag.name);
      if (dup) continue;
      seenNames.add(tag.name);
      out.add(tag);
    }
    return out;
  }

  /// 声优名归一：`[{id, name}]` 或纯字符串数组
  static List<String> parseVoiceActorNames(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      final name = switch (item) {
        String s => s.trim(),
        Map m => (m['name'] as String?)?.trim() ?? '',
        _ => '',
      };
      if (name.isNotEmpty && !out.contains(name)) out.add(name);
    }
    return out;
  }
}

/// 在线作品分页结果
class OnlineWorkPage {
  const OnlineWorkPage({
    required this.works,
    required this.currentPage,
    required this.pageSize,
    required this.totalCount,
  });

  final List<OnlineWork> works;
  final int currentPage;
  final int pageSize;
  final int totalCount;

  bool get hasMore => currentPage * pageSize < totalCount;

  factory OnlineWorkPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'];
    final p = pagination is Map ? Map<String, dynamic>.from(pagination) : const {};
    return OnlineWorkPage(
      works: (json['works'] as List?)
              ?.whereType<Map>()
              .map((w) => OnlineWork.fromJson(Map<String, dynamic>.from(w)))
              .toList() ??
          const [],
      currentPage: (p['currentPage'] as num?)?.toInt() ?? 1,
      pageSize: (p['pageSize'] as num?)?.toInt() ?? 0,
      totalCount: (p['totalCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 登录用户（`GET /api/auth/me`）。
///
/// 未登录时服务端同样返回 200，只是 `user.loggedIn = false` —— 所以「令牌失效」
/// 要靠这个字段判断，不能只看状态码（1.93.0 实测）。
class OnlineUser {
  const OnlineUser({
    required this.loggedIn,
    this.name = '',
    this.group = '',
    this.email,
  });

  final bool loggedIn;
  final String name;

  /// `user` / `admin`
  final String group;
  final String? email;

  static const guest = OnlineUser(loggedIn: false);

  /// 吃整个 `/api/auth/me` 响应体（`{"user":{...},"auth":true,"reg":true}`）。
  /// `user` 段缺失时按未登录处理。
  factory OnlineUser.fromJson(Map<String, dynamic> json) {
    final raw = json['user'];
    if (raw is! Map) return guest;
    final user = Map<String, dynamic>.from(raw);
    return OnlineUser(
      loggedIn: user['loggedIn'] as bool? ?? false,
      name: (user['name'] as String?)?.trim() ?? '',
      group: (user['group'] as String?)?.trim() ?? '',
      email: user['email'] as String?,
    );
  }
}

/// 在线歌单 —— asmr.one 的「收藏」体系（1.93.0 接入）。
///
/// 三条实测结论决定了这个类的形状：
/// ① **`id` 是 UUID 字符串**，不是数字，别当 int 用；
/// ② **系统保留歌单的名字是原始 key**（`__SYS_PLAYLIST_LIKED` / `__SYS_PLAYLIST_MARKED`），
///    服务端不做本地化，中文名要 Hiko 自己映射（见 [displayName]）；
/// ③ 系统保留歌单**不可改名、不可删除**（服务端两道校验都会拒），
///    所以 UI 要靠 [editable] 把入口收起来。
class OnlinePlaylist {
  const OnlinePlaylist({
    required this.id,
    required this.name,
    this.userName = '',
    this.privacy = 0,
    this.locale = '',
    this.worksCount = 0,
    this.latestWorkId,
    this.mainCoverUrl = '',
    this.exist,
  });

  /// 「我喜欢的」：asmr.one 网页里点爱心收藏的作品落到这里
  static const sysLiked = '__SYS_PLAYLIST_LIKED';

  /// 「我标记的」：网页版「标记」按钮的目标歌单
  static const sysMarked = '__SYS_PLAYLIST_MARKED';

  /// privacy 枚举（实测）：0 私享 / 1 不公开 / 2 公开
  static const privacyOptions = <(int, String)>[
    (0, '私享'),
    (1, '不公开'),
    (2, '公开'),
  ];

  /// 新建歌单默认私享（裁决 Q12=A，与网页版一致）
  static const defaultPrivacy = 0;

  final String id;
  final String name;
  final String userName;
  final int privacy;
  final String locale;
  final int worksCount;
  final int? latestWorkId;
  final String mainCoverUrl;

  /// 该作品是否在这个歌单里。只有
  /// `get-work-exist-status-in-my-playlists` 的返回带这个字段，其余端点恒为 null。
  ///
  /// 三态而非 bool：null = 不知道，false = 明确不在。省略掉这个区别的话，
  /// 「没查过」会被当成「没收藏」，UI 就会先把勾去掉再跳回来。
  final bool? exist;

  bool get isLiked => name == sysLiked;
  bool get isMarked => name == sysMarked;
  bool get isSystem => isLiked || isMarked;

  /// 能否改名 / 删除。系统保留歌单两端点都会被服务端拒绝，入口直接不显示
  bool get editable => !isSystem;

  /// 展示名：系统 key 映射成中文，普通歌单用原名
  String get displayName => switch (name) {
        sysLiked => '我喜欢的',
        sysMarked => '我标记的',
        _ => name.trim().isEmpty ? '未命名歌单' : name,
      };

  String get privacyLabel => switch (privacy) {
        1 => '不公开',
        2 => '公开',
        _ => '私享',
      };

  /// 空歌单的封面是服务端占位图（`/statics/no-image.jpg`），不是绝对地址
  bool get hasCover =>
      mainCoverUrl.trim().isNotEmpty && !mainCoverUrl.contains('no-image');

  factory OnlinePlaylist.fromJson(Map<String, dynamic> json) {
    return OnlinePlaylist(
      id: (json['id'] as String?)?.trim() ?? '',
      name: (json['name'] as String?) ?? '',
      userName: (json['user_name'] as String?)?.trim() ?? '',
      privacy: (json['privacy'] as num?)?.toInt() ?? defaultPrivacy,
      locale: (json['locale'] as String?) ?? '',
      worksCount: (json['works_count'] as num?)?.toInt() ?? 0,
      latestWorkId: (json['latestWorkID'] as num?)?.toInt(),
      mainCoverUrl: (json['mainCoverUrl'] as String?) ?? '',
      exist: json['exist'] as bool?,
    );
  }

  OnlinePlaylist copyWith({
    String? name,
    int? privacy,
    String? locale,
    int? worksCount,
    int? latestWorkId,
    String? mainCoverUrl,
    bool? exist,
    bool clearExist = false,
  }) =>
      OnlinePlaylist(
        id: id,
        name: name ?? this.name,
        userName: userName,
        privacy: privacy ?? this.privacy,
        locale: locale ?? this.locale,
        worksCount: worksCount ?? this.worksCount,
        latestWorkId: latestWorkId ?? this.latestWorkId,
        mainCoverUrl: mainCoverUrl ?? this.mainCoverUrl,
        exist: clearExist ? null : (exist ?? this.exist),
      );
}

/// 歌单分页结果（`/api/playlist/get-playlists` 与 `get-work-exist-status-in-my-playlists`
/// 共用同一个响应形状）
class OnlinePlaylistPage {
  const OnlinePlaylistPage({
    required this.playlists,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<OnlinePlaylist> playlists;
  final int page;
  final int pageSize;
  final int totalCount;

  factory OnlinePlaylistPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'];
    final p = pagination is Map ? Map<String, dynamic>.from(pagination) : const {};
    return OnlinePlaylistPage(
      playlists: (json['playlists'] as List?)
              ?.whereType<Map>()
              .map((w) => OnlinePlaylist.fromJson(Map<String, dynamic>.from(w)))
              .toList() ??
          const [],
      page: (p['page'] as num?)?.toInt() ?? 1,
      pageSize: (p['pageSize'] as num?)?.toInt() ?? 0,
      totalCount: (p['totalCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 歌单内作品分页结果（`/api/playlist/get-playlist-works`）。
/// work 对象与 `/api/works` 同构，所以直接复用 [OnlineWork]。
class PlaylistWorkPage {
  const PlaylistWorkPage({
    required this.works,
    required this.page,
    required this.pageSize,
    required this.totalCount,
  });

  final List<OnlineWork> works;
  final int page;
  final int pageSize;
  final int totalCount;

  factory PlaylistWorkPage.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'];
    final p = pagination is Map ? Map<String, dynamic>.from(pagination) : const {};
    return PlaylistWorkPage(
      works: (json['works'] as List?)
              ?.whereType<Map>()
              .map((w) => OnlineWork.fromJson(Map<String, dynamic>.from(w)))
              .toList() ??
          const [],
      page: (p['page'] as num?)?.toInt() ?? 1,
      pageSize: (p['pageSize'] as num?)?.toInt() ?? 0,
      totalCount: (p['totalCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 多选歌单菜单确认后要发的**差分**（裁决 Q8=B）。
///
/// 刻意不做「全量重写」：服务端只有 add / remove 两个端点，没有 set，
/// 而且全量重写会把「网页端刚加进别的歌单」这类并发改动抹掉。
@immutable
class PlaylistDiff {
  const PlaylistDiff({required this.addTo, required this.removeFrom});

  /// 需要加入的歌单 id（UUID）
  final List<String> addTo;

  /// 需要移出的歌单 id（UUID）
  final List<String> removeFrom;

  static const empty = PlaylistDiff(addTo: [], removeFrom: []);

  bool get isEmpty => addTo.isEmpty && removeFrom.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// 需要发出的请求条数（每个歌单一条）
  int get requestCount => addTo.length + removeFrom.length;

  @override
  String toString() => 'PlaylistDiff(+${addTo.length}/-${removeFrom.length})';
}

/// 算出「当前勾选 → 目标勾选」的最小差分。纯函数，单测覆盖。
///
/// [current] 是打开菜单时该作品所属的歌单集合，[desired] 是用户点完确认的集合。
/// 顺序沿用两个集合自己的迭代顺序（即歌单展示顺序），便于测试断言稳定。
PlaylistDiff planPlaylistDiff({
  required Set<String> current,
  required Set<String> desired,
}) =>
    PlaylistDiff(
      addTo: desired.difference(current).toList(),
      removeFrom: current.difference(desired).toList(),
    );

/// 曲目树里的单个文件（`GET /api/tracks/{workId}`，已拍平）。
///
/// 服务端返回的是嵌套 folder/file 树，这里拍平成一维：
/// 文件夹只用于字幕配对与展示分组，不参与播放。
class OnlineTrack {
  const OnlineTrack({
    required this.hash,
    required this.title,
    required this.type,
    this.size = 0,
    this.duration = 0,
    this.mediaStreamUrl,
    this.relativePath = '',
    this.lyricsHash,
    this.lyricsTitle,
  });

  /// 服务端 hash，形如 `1657200/1937305`（作品号/文件号），媒体流端点用
  final String hash;
  final String title;

  /// `audio` / `text` / `image` / `video`
  final String type;
  final int size;

  /// 文件时长（秒）。服务端给的是浮点（如 `291.4832`），字幕/图片文件为 0。
  ///
  /// 1.91.0 补上：原先只取了 size，导致在线详情页无法像本地那样在曲目行显示时长。
  final double duration;

  /// 服务端给的 CDN 直链（可能为空，需回退到 `/api/media/stream/{hash}`）
  final String? mediaStreamUrl;

  /// 文件夹相对路径（仅展示用，如 `02英語/01：mp3`）
  final String relativePath;

  /// 同目录同名的字幕文件 hash（播放时懒加载，喂给现有歌词系统）
  final String? lyricsHash;
  final String? lyricsTitle;

  bool get isAudio => type == 'audio';
  bool get isText => type == 'text';

  /// 是否可作为音频播放：服务端把 mp3/m4b/wav 都标 audio，视频轨也标 audio，
  /// 这里按标题扩展名排除明显不是音频的（.mp4 等由播放器自行处理，不排除）
  bool get playable => isAudio;

  OnlineTrack copyWith({String? lyricsHash, String? lyricsTitle}) => OnlineTrack(
        hash: hash,
        title: title,
        type: type,
        size: size,
        duration: duration,
        mediaStreamUrl: mediaStreamUrl,
        relativePath: relativePath,
        lyricsHash: lyricsHash ?? this.lyricsHash,
        lyricsTitle: lyricsTitle ?? this.lyricsTitle,
      );
}

/// 曲目树节点：完整还原服务端的目录层级（**不限深度**，实测有 0~3 层）。
///
/// 与拍平的 [OnlineTrack] 并存：拍平列表喂播放器（构造内存态 Album），
/// 节点树只喂详情页渲染（分组、折叠、目录聚合计数）。二者通过 hash 对应。
sealed class OnlineNode {
  const OnlineNode();
}

/// 目录节点。[audioCount] / [totalSeconds] 由子节点递归聚合而来——
/// 服务端 folder 节点只有 `type` + `title`，这两个数是我们自己算的
/// （asmr.one 前端也是这么显示的：「2 项目, 36min」）。
final class OnlineFolderNode extends OnlineNode {
  OnlineFolderNode(this.title, this.children)
      : audioCount = children.fold(
          0,
          (sum, child) => sum + switch (child) {
            OnlineFileNode(:final track) => track.playable ? 1 : 0,
            OnlineFolderNode(:final audioCount) => audioCount,
          },
        ),
        totalSeconds = children.fold(
          0.0,
          (sum, child) => sum + switch (child) {
            OnlineFileNode(:final track) =>
              track.playable ? track.duration : 0.0,
            OnlineFolderNode(:final totalSeconds) => totalSeconds,
          },
        );

  final String title;
  final List<OnlineNode> children;

  /// 递归聚合：该目录下（含子目录）可播放音频的条数
  final int audioCount;

  /// 递归聚合：该目录下（含子目录）可播放音频的时长合计（秒）
  final double totalSeconds;
}

/// 文件节点（音频 / 字幕 / 图片 / 视频）
final class OnlineFileNode extends OnlineNode {
  const OnlineFileNode(this.track);

  final OnlineTrack track;
}

/// 递归收集节点树里所有可播放音频（按树内顺序），供「播放该目录」使用
List<OnlineTrack> playableIn(OnlineNode node) => switch (node) {
      OnlineFileNode(:final track) => track.playable ? [track] : const [],
      OnlineFolderNode(:final children) => [
          for (final child in children) ...playableIn(child),
        ],
    };

/// 递归收集节点树里所有目录的路径键（与 [OnlineTrack.relativePath] 同一套拼法），
/// 供「折叠全部 / 展开全部」用。
///
/// 只收**含可播放音频**的目录 —— 详情页只渲染这类目录，把仅存字幕/图片的
/// 空目录也算进来的话，「全部已折叠」这个状态永远达不到。
List<String> folderKeysIn(List<OnlineNode> nodes, [String parent = '']) {
  final out = <String>[];
  for (final node in nodes) {
    if (node is! OnlineFolderNode || node.audioCount == 0) continue;
    final path = parent.isEmpty ? node.title : '$parent/${node.title}';
    out.add(path);
    out.addAll(folderKeysIn(node.children, path));
  }
  return out;
}

/// 分页条的页码序列：`[1, null, 4, 5, 6, null, 3123]`。
///
/// `null` 表示省略号。首页、末页与当前页 ±[radius] 恒出现；实测全站 62453 件，
/// 20 条/页 = 3123 页，纯页码条放不下，所以只保留这三段。
List<int?> buildPageItems(int current, int total, {int radius = 2}) {
  if (total <= 0) return const [];
  final wanted = <int>{1, total};
  for (var page = current - radius; page <= current + radius; page++) {
    if (page >= 1 && page <= total) wanted.add(page);
  }
  final sorted = wanted.toList()..sort();
  final out = <int?>[];
  int? prev;
  for (final page in sorted) {
    if (prev != null && page - prev > 1) out.add(null);
    out.add(page);
    prev = page;
  }
  return out;
}

/// 标签（筛选用，来自 `/api/tags/`）
class OnlineTag {
  const OnlineTag({required this.id, required this.name, this.count = 0});

  final int id;
  final String name;
  final int count;

  factory OnlineTag.fromJson(Map<String, dynamic> json) {
    final i18n = json['i18n'];
    var name = (json['name'] as String?)?.trim() ?? '';
    if (i18n is Map) {
      final zh = i18n['zh-cn'];
      if (zh is Map) {
        final zhName = zh['name'];
        if (zhName is String && zhName.trim().isNotEmpty) name = zhName.trim();
      }
    }
    return OnlineTag(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: name,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 在线列表排序项（1.92.0 起对齐 asmr.one 的「排序」菜单形态）。
///
/// 与旧 `OnlineOrder` 的区别：**方向写进条目名**（「销量倒序」而不是「销量」+ 一个
/// 独立的升降序开关），所以整份菜单是一个扁平列表，没有「再点一次反转」这种隐藏状态。
/// 条目名、顺序、以及 5 项的取舍都来自用户裁决（Q5=甲）。
///
/// 服务端 `order` 参数走白名单，白名单外的值一律 **400**（实测 `source_id` 就 400）。
/// 已实测可用的键：`create_date` / `release` / `dl_count` / `price` /
/// `rate_average_2dp` / `review_count` / `id` / `rating`。
/// 其中 `rating`（asmr.one 的「我的评价倒序」）匿名请求返回 0 条 —— 它要登录，
/// Hiko 不做账号体系，因此**刻意不在枚举里**。
enum OnlineSort {
  /// 本站最近收录（`create_date`）。实测与「发售日期倒序」第一页结果完全相同，
  /// 但深层会分叉，两者都留（用户裁决甲方案）。
  createDate('create_date', '最新收录'),

  releaseDesc('release', '发售日期倒序'),

  dlCountDesc('dl_count', '销量倒序'),

  rateDesc('rate_average_2dp', '评价倒序'),

  /// asmr.one 菜单上的「RJ 号倒序」。实测服务端的 `id` 对 RJ 作品**数值上就等于
  /// RJ 号**（`id=1657200` ↔ `RJ01657200`），近年的 BJ/VJ 作品才被塞进 `1000000xx`
  /// 段，所以这一项约等于「DLsite 上新顺序」，与「本站最近收录」不是一回事。
  rjDesc('id', 'RJ 号倒序');

  const OnlineSort(this.key, this.label);

  final String key;
  final String label;

  /// 甲方案 5 项**全部是倒序**，所以不设方向字段、客户端直接拼 `sort=desc`。
  /// asmr.one 菜单里的「顺序」变体（发售日期顺序 / 价格顺序 / RJ 号顺序）本轮未采纳；
  /// 将来要加就把方向加回枚举，别在调用点散落魔法值。
  static const sortParam = 'desc';

  /// 预设（列表页顶部那两个 chip）指向的排序项：热门 = 销量，最新 = 发售日期。
  /// chip 点击后就把排序切到这里，之后用户可自由改排序（裁决 Q4=A）。
  static const popularPreset = OnlineSort.dlCountDesc;
  static const latestPreset = OnlineSort.releaseDesc;
}

/// 从根到 [hash] 所在文件之间的**目录路径链**（每一级都需要展开才能露出该文件），
/// 由浅到深排列，可直接丢进详情页的展开集合。
///
/// 供详情页「把正在播放的那一行展开出来」用（裁决 Q2）。两种「无事可做」都返回
/// 空列表：文件不在任何目录里（直接在作品根下，本来就可见），以及 hash 不在树里。
///
/// 路径键与 [OnlineTrack.relativePath] / [folderKeysIn] 同一套拼法。
List<String> pathToHash(List<OnlineNode> nodes, String hash, [String parent = '']) {
  for (final node in nodes) {
    switch (node) {
      case OnlineFolderNode(:final title, :final children):
        final path = parent.isEmpty ? title : '$parent/$title';
        // 文件直接躺在这一层
        final here = children.any(
          (child) => child is OnlineFileNode && child.track.hash == hash,
        );
        if (here) return [path];
        final deeper = pathToHash(children, hash, path);
        if (deeper.isNotEmpty) return [path, ...deeper];
      case OnlineFileNode():
        break; // 根级文件无目录可展开
    }
  }
  return const [];
}

/// 音轨标题展示：剥掉扩展名。在线作品的标题一律带 `.mp3` / `.wav` 这类后缀
/// （asmr.one 网页也照原样显示），但 Hiko 播放器里的曲目名是不带的，
/// 详情页跟着播放器走，两处才不会对不上。
String onlineTrackDisplayName(String title) {
  final name = title.trim();
  if (name.isEmpty) return '未命名音轨';
  final dot = name.lastIndexOf('.');
  if (dot > 0 && name.length - dot <= 6) return name.substring(0, dot);
  return name;
}

/// 作品网页地址。
///
/// 官方实例的 API 域名不是网页域名：实测 `https://api.asmr.one/works/{id}`
/// 返回 **404**，网页在 `www.asmr.one`。四个官方镜像指向同一站，统一映射过去。
/// 自建 Kikoeru 的 API 与网页同 host，直接拼即可。
String onlineWorkPageUrl(String serverBase, int workId) {
  final base = serverBase.trim().replaceAll(RegExp(r'/+$'), '');
  if (base.isEmpty || base.contains('api.asmr')) {
    return 'https://www.asmr.one/works/$workId';
  }
  return '$base/works/$workId';
}

/// 下载量等大数字的中文习惯缩写：`307937` → `30.8万`
String formatOnlineCount(int value) {
  if (value >= 100000000) return '${(value / 100000000).toStringAsFixed(1)}亿';
  if (value >= 10000) return '${(value / 10000).toStringAsFixed(1)}万';
  return '$value';
}

/// 日期展示：`2026-06-27`
String formatOnlineDate(DateTime? date) {
  if (date == null) return '';
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '${date.year}-$m-$d';
}
