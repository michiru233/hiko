import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'online_blacklist.dart';
import 'online_models.dart';

/// 在线请求异常（含可展示的中文说明）
class KikoeruException implements Exception {
  KikoeruException(this.message, [this.cause, this.statusCode]);

  final String message;
  final Object? cause;

  /// HTTP 状态码；网络层失败（连不上、超时）为 null。
  /// 调用方据它区分「令牌过期（401）」与「网络不通」。
  final int? statusCode;

  /// 令牌失效：401，或服务端在鉴权端点回 `{"error":"invalid token"}`
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => cause == null ? message : '$message（$cause）';
}

/// Kikoeru 兼容服务器的 HTTP 客户端（asmr.one 即该协议的公共实例）。
///
/// 实测确认的关键点（2026-09-25/26，见 .workbuddy/memory/2026-09-25.md）：
/// - **浏览/搜索/详情/曲目树/封面/字幕/音频流全部匿名可用**，无需 token；
///   需要登录的是账号与歌单（收藏）接口，见本文件「账号 / 歌单」两节。
/// - 端点是**单数**形式：`/api/work/{id}`、`/api/tracks/{id}`；
///   复数形式 `/api/works/{id}` 会返回 401，不要混用。
/// - 音频流 `/api/media/stream/{hash}` 返回 302 跳转到带时效签名的 CDN 直链，
///   播放器跟随重定向即可，支持 Range。
/// - 官方实例有 4 个镜像域名，任一可用即可；自建服务器不做镜像回退。
class KikoeruClient {
  KikoeruClient({
    required String baseUrl,
    this.proxy = '',
    String token = '',
    Duration? timeout,
  })  : _configuredBase = normalizeBase(baseUrl),
        token = sanitizeToken(token),
        _timeout = timeout ?? const Duration(seconds: 20);

  /// 官网镜像族（仅当地址属于该族时才启用回退，自建服务器绝不跨站重试）
  static const officialMirrors = <String>[
    'https://api.asmr.one',
    'https://api.asmr-200.com',
    'https://api.asmr-100.com',
    'https://api.asmr-300.com',
  ];

  /// 列表默认取 20 条/页
  static const defaultPageSize = 20;

  /// **playlist 系列端点**的 `pageSize` 硬上限 = 100。
  ///
  /// 1.93.1 实测：`get-playlists` / `get-playlist-works` /
  /// `get-work-exist-status-in-my-playlists` 三个端点**共用同一个校验器**，
  /// 传 200/500 一律 400 `{"errors":[{"msg":"Invalid value","param":"pageSize"}]}`
  /// —— 是**整个请求被拒**，不是静默截断。
  ///
  /// 注意 `/api/works` 那一系（含 `/api/search`、`/api/tags/*`）能吃到 500，
  /// 是**另一套校验**；`defaultPageSize` 与这个常量别互相套用。
  static const playlistMaxPageSize = 100;

  /// playlist 系端点的 `pageSize` 统一夹到 [1, playlistMaxPageSize]。
  ///
  /// 越界时服务端拒整个请求，所以必须在**发出之前**就地纠正 ——
  /// 这样调用方随便传也不会把 400 透到界面上（1.93.0 的刷新失败就是这么来的）。
  static int clampPlaylistPageSize(int value) =>
      value < 1 ? 1 : (value > playlistMaxPageSize ? playlistMaxPageSize : value);

  /// `get-work-exist-status-in-my-playlists` 最多翻几页（纯粹防死循环；
  /// 按 [playlistMaxPageSize] 算，能覆盖 2000 个歌单，远超真实用量）。
  static const _maxStatusPages = 20;

  /// 封面尺寸白名单（实测：只有这三个值合法，其余一律 400 `{"error":"type: Invalid value"}`）。
  ///
  /// **1.93.0 起列表不再用它**：`240x240` 实际返回 240×180，卡片是 200–260 逻辑像素、
  /// Retina 下要 400–520 物理像素，`BoxFit.cover` 裁成方形后只剩 180×180 可用，
  /// 等于放大 2.4–2.9 倍 —— 这就是「主界面封面模糊、详情页正常」的全部原因。
  /// 服务端**没有中间档**（`sam` 更小，只有 100×75），所以列表与详情统一走原图。
  /// asmr.one 自己的列表用的也是 `type=main`，与这里一致。
  static const coverThumbSize = '240x240';

  /// 原图（560×420）。与不带 `type` 参数完全同一张图（md5 相同），
  /// 但显式写出参数能让意图可读，也方便将来服务端真加了中间档时替换。
  static const coverMainSize = 'main';

  final String _configuredBase;
  final String proxy;

  /// 登录令牌（**原始 JWT，不含 `Bearer ` 前缀**）。
  ///
  /// 实测：请求头是 `Authorization: Bearer <jwt>`，而用户从工具里复制出来的
  /// 字符串常常带一截 `__q_strn|` 之类的噪声前缀，带上去服务端直接回
  /// `{"error":"invalid token"}` —— 所以 [sanitizeToken] 会先把它剥掉。
  final String token;

  final Duration _timeout;

  /// 会话内记住的可用地址（镜像回退命中后不再每次重试坏地址）
  String? _activeBase;

  String get baseUrl => _activeBase ?? _configuredBase;
  String get configuredBase => _configuredBase;
  bool get isOfficial => _configuredBase.contains('api.asmr');

  /// 是否带上登录令牌
  bool get authenticated => token.isNotEmpty;

  /// 同一服务器、**不带令牌**的副本。登录端点用：网页端在那个端点上把
  /// Authorization 显式置 null，这里保持同样的语义（实测并非硬要求，
  /// 见 [login] 的注释）。
  KikoeruClient anonymous() => KikoeruClient(
        baseUrl: _configuredBase,
        proxy: proxy,
        timeout: _timeout,
      );

  /// 令牌归一：去掉首尾空白与**所有内部空白**（换行、空格 —— JWT 本体不含空白）、
  /// 剥掉 `Bearer ` 前缀、剥掉 `__q_strn|` 这类噪声前缀。
  ///
  /// 只取最后一个 `|` 之后的部分，因为 JWT 本体不含 `|`。
  static String sanitizeToken(String raw) {
    var value = raw.replaceAll(RegExp(r'\s'), '');
    if (value.isEmpty) return '';
    // 空白已去掉，所以这里只看头 6 个字符，不能匹配 'bearer '
    if (value.length > 6 && value.substring(0, 6).toLowerCase() == 'bearer') {
      value = value.substring(6);
    }
    final bar = value.lastIndexOf('|');
    if (bar >= 0) value = value.substring(bar + 1);
    return value.trim();
  }

  /// 地址归一：补 scheme、去尾斜杠。`api.asmr.one` → `https://api.asmr.one`
  static String normalizeBase(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return officialMirrors.first;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      // 本机/内网自建服务器默认 http，公网默认 https
      final isLocal = value.contains('localhost') ||
          value.startsWith('127.0.0.1') ||
          value.startsWith('192.168.') ||
          value.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(value);
      value = '${isLocal ? 'http' : 'https'}://$value';
    }
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  /// 请求候选地址：官方实例主地址优先，其余镜像作回退
  List<String> get _candidates {
    final active = _activeBase;
    if (active != null) {
      // 命中过的地址优先，其余仍作兜底（网络切换后可能换镜像更快）
      return [active, ..._mirrorsFor(_configuredBase).where((m) => m != active)];
    }
    return _mirrorsFor(_configuredBase);
  }

  static List<String> _mirrorsFor(String base) {
    if (!base.contains('api.asmr')) return [base];
    return [base, ...officialMirrors.where((m) => m != base)];
  }

  // ---------------------------------------------------------------- 端点

  /// 作品列表（`GET /api/works`）。
  ///
  /// [excludeKeyword] 非空时**改走搜索接口** `/api/search/{excludeKeyword}` ——
  /// 因为 `/api/works` 会**静默忽略**一切排除类参数（1.95.0 实测：带 `keyword`、
  /// `excludeTags` 都照样返回全站量），这是把黑名单做在服务端的唯一路径。
  ///
  /// 实测「空关键词的搜索」与 `/api/works` 在 5 个排序键下**逐位完全相同**，
  /// 所以换端点本身不改变结果集与顺序 —— 只是把被屏蔽的作品滤掉了。
  /// 唯一的差异是：排序键相等的**并列项 tie-break 会变**（抓到了一例）。
  Future<OnlineWorkPage> fetchWorks({
    int page = 1,
    int pageSize = defaultPageSize,
    OnlineSort sort = OnlineSort.createDate,
    bool subtitleOnly = false,
    String excludeKeyword = '',
  }) async {
    final query = {
      'page': '$page',
      'pageSize': '$pageSize',
      'order': sort.key,
      'sort': OnlineSort.sortParam,
      if (subtitleOnly) 'subtitle': '1',
    };
    final exclude = excludeKeyword.trim();
    final json = exclude.isEmpty
        ? await _getObject('/api/works', query)
        : await _getObject(
            '/api/search/${Uri.encodeComponent(exclude)}',
            query,
          );
    return OnlineWorkPage.fromJson(json);
  }

  /// 关键词搜索（`GET /api/search/{keyword}`，支持与列表相同的分页/排序参数）
  ///
  /// [excludeKeyword] 会拼在关键词**前面**（与 asmr.one 的 `globalFilter` 同一做法）。
  /// 注意「两边都空才早退」：只有排除项、没有关键词也是一次合法请求
  /// （实测 `$-tag:X$` 单独就能筛出「全站去掉 X」）。
  Future<OnlineWorkPage> searchWorks(
    String keyword, {
    int page = 1,
    int pageSize = defaultPageSize,
    OnlineSort sort = OnlineSort.createDate,
    String excludeKeyword = '',
  }) async {
    final kw = keyword.trim();
    final exclude = excludeKeyword.trim();
    if (kw.isEmpty && exclude.isEmpty) {
      return const OnlineWorkPage(
          works: [], currentPage: 1, pageSize: 0, totalCount: 0);
    }
    final merged = [exclude, kw].where((s) => s.isNotEmpty).join(' ');
    final json = await _getObject('/api/search/${Uri.encodeComponent(merged)}', {
      'page': '$page',
      'pageSize': '$pageSize',
      'order': sort.key,
      'sort': OnlineSort.sortParam,
    });
    return OnlineWorkPage.fromJson(json);
  }

  /// 按标签筛选。
  ///
  /// 无黑名单时走结构化端点 `GET /api/tags/{tagId}/works`（1.94.0 裁决 Q2=甲）。
  /// [excludeKeyword] 非空时**必须**并进搜索 —— 搜索接口不支持「结构化标签 + 排除项」
  /// 的组合，而结构化标签端点又会忽略排除参数，所以改用**实测等价**的
  /// `$tag:<名>$`：三个标签逐一比对过 totalCount 与逐位顺序，完全相同。
  Future<OnlineWorkPage> fetchWorksByTag(
    OnlineTag tag, {
    int page = 1,
    int pageSize = defaultPageSize,
    OnlineSort sort = OnlineSort.dlCountDesc,
    String excludeKeyword = '',
  }) async {
    final exclude = excludeKeyword.trim();
    final query = {
      'page': '$page',
      'pageSize': '$pageSize',
      'order': sort.key,
      'sort': OnlineSort.sortParam,
    };
    // 名字为空（坏数据）时只能退回结构化端点：那样黑名单这一条就不生效，
    // 但「按标签筛对了、只是没滤黑名单」比「给出了没筛的结果」好。
    final path = (exclude.isEmpty || tag.name.trim().isEmpty)
        ? '/api/tags/${tag.id}/works'
        : '/api/search/${Uri.encodeComponent('${tagIncludeTerm(tag.name.trim())} $exclude')}';
    final json = await _getObject(path, query);
    return OnlineWorkPage.fromJson(json);
  }

  /// 作品详情（`GET /api/work/{id}?v=2`，补全 tags / vas / 封面）
  Future<OnlineWork> fetchWork(int id) async {
    final json = await _getObject('/api/work/$id', {'v': '2'});
    return OnlineWork.fromJson(json);
  }

  /// 曲目树（`GET /api/tracks/{id}`），已拍平并完成字幕配对
  Future<List<OnlineTrack>> fetchTracks(int workId) async {
    final raw = await _getDecoded('/api/tracks/$workId');
    if (raw is! List) return const [];
    return parseTrackTree(raw);
  }

  /// 曲目树：一次请求同时给出拍平列表（喂播放器）与层级节点树（喂详情页渲染）。
  ///
  /// 详情页既要按 asmr.one 的目录层级分组展示，又要一份扁平的播放序，
  /// 所以两个形态在同一个响应上解析，避免重复请求。
  Future<({List<OnlineTrack> tracks, List<OnlineNode> tree})> fetchTrackTree(
      int workId) async {
    final raw = await _getDecoded('/api/tracks/$workId');
    if (raw is! List) {
      return (tracks: const <OnlineTrack>[], tree: const <OnlineNode>[]);
    }
    final tracks = parseTrackTree(raw);
    return (tracks: tracks, tree: parseTrackNodes(raw, tracks));
  }

  /// 解析服务端嵌套曲目树：拍平成一维文件列表 + 字幕配对（纯函数，单测覆盖）
  static List<OnlineTrack> parseTrackTree(List nodes) {
    final files = <OnlineTrack>[];
    _flatten(nodes, '', files);
    return _attachLyrics(files);
  }

  /// 在已拍平（且已配对字幕）的 [flat] 基础上还原层级节点树，**不限深度**。
  ///
  /// 不重新构造 [OnlineTrack]，而是按 hash 取回同一条记录 —— 这样节点树里的
  /// 曲目天然带着字幕配对结果，不会出现两份不同步的副本。
  static List<OnlineNode> parseTrackNodes(
      List nodes, List<OnlineTrack> flat) {
    final byHash = {for (final track in flat) track.hash: track};
    return _buildNodes(nodes, byHash);
  }

  static List<OnlineNode> _buildNodes(
      List nodes, Map<String, OnlineTrack> byHash) {
    final out = <OnlineNode>[];
    for (final node in nodes) {
      if (node is! Map) continue;
      final map = Map<String, dynamic>.from(node);
      final type = (map['type'] as String?) ?? '';
      final title = (map['title'] as String?) ?? '';
      if (type == 'folder') {
        final children = map['children'];
        out.add(OnlineFolderNode(
          title,
          children is List ? _buildNodes(children, byHash) : const [],
        ));
        continue;
      }
      final hash = map['hash'];
      if (hash is! String || hash.isEmpty) continue;
      final track = byHash[hash];
      if (track == null) continue;
      out.add(OnlineFileNode(track));
    }
    return out;
  }

  /// 拉取文本文件内容（字幕等），失败返回 null（歌词缺失不应影响播放）
  Future<String?> fetchText(String hash) async {
    try {
      return await _getString(Uri.parse('$baseUrl/api/media/stream/$hash'));
    } catch (_) {
      return null;
    }
  }

  /// 全量标签表（422 个 / 约 72KB，可缓存）
  Future<List<OnlineTag>> fetchTags() async {
    final raw = await _getDecoded('/api/tags/');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((t) => OnlineTag.fromJson(Map<String, dynamic>.from(t)))
        .toList();
  }

  /// 连通性探测（`GET /api/health`，未登录也返回 200 OK）
  Future<bool> ping() async {
    try {
      await _getString(Uri.parse('$baseUrl/api/health'));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- 账号
  //
  // 1.93.0 接入。asmr.one 的账号体系实测结论（全部真机跑过）：
  // - 登录 = `POST /api/auth/me {name, password}` → `{token}`；错密码是
  //   401 `{"error":"用户名或密码错误."}`，中文原文可直接透给用户。
  // - 无 refresh 端点、**无服务端登出端点**（网页端登出只是清 localStorage），
  //   令牌有效期 30 天（`expiresIn: 2592000`），过期只能重新登录（裁决 Q7=A）。
  // - 令牌失效时 `/api/auth/me` 依然返回 **200**，只是 `user.loggedIn = false`，
  //   所以判断登录态要看字段而不是状态码。

  /// 当前登录态（`GET /api/auth/me`）。未登录也返回 200，故不抛异常
  Future<OnlineUser> fetchMe() async {
    final json = await _getObject('/api/auth/me');
    return OnlineUser.fromJson(json);
  }

  /// 登录并取回 JWT（`POST /api/auth/me`）。
  ///
  /// 用 [anonymous] 副本发请求：asmr.one 网页端在这个端点上显式把 Authorization
  /// 置 null，这里跟着走。实测带着一个无意义的 Bearer 也能正常走到凭证校验
  /// （三种 Content-Type 形态都返回同样的 401「用户名或密码错误.」），
  /// 所以这不是硬要求 —— 只是不给自己制造「旧令牌参与登录」这种可能性。
  Future<String> login({required String name, required String password}) async {
    final json = await anonymous()._postJson(
      '/api/auth/me',
      {'name': name.trim(), 'password': password},
    );
    final raw = json is Map ? json['token'] : null;
    if (raw is! String || raw.trim().isEmpty) {
      throw KikoeruException('登录成功但服务器没有返回令牌');
    }
    return sanitizeToken(raw);
  }

  // ---------------------------------------------------------------- 歌单（收藏）
  //
  // asmr.one 的「收藏」就是歌单（playlist）体系，没有独立的收藏端点。
  // 参数形态**两套，别混**（实测）：
  // - `create-playlist` 的 `works` 吃 **source_id 字符串**（`"RJ01657200"`）
  // - `add-works-to-playlist` / `remove-works-from-playlist` 吃**数字 work id**
  //   （传字符串会 400 `Invalid value`）

  /// 我的歌单列表（`GET /api/playlist/get-playlists`）。
  ///
  /// `filterBy` 实测 `all`/`owned`/`liked` **都返回全部歌单**（服务端没实现区分），
  /// 所以固定用 `all`，不要指望它过滤。
  Future<OnlinePlaylistPage> fetchPlaylists({
    int page = 1,
    int pageSize = playlistMaxPageSize,
  }) async {
    final json = await _getObject('/api/playlist/get-playlists', {
      'page': '$page',
      'pageSize': '${clampPlaylistPageSize(pageSize)}',
      'filterBy': 'all',
    });
    return OnlinePlaylistPage.fromJson(json);
  }

  /// 歌单内的作品（`GET /api/playlist/get-playlist-works`）。
  /// work 对象与 `/api/works` 同构，多 `playlist_rel_created_at` / `_updated_at`。
  Future<PlaylistWorkPage> fetchPlaylistWorks(
    String playlistId, {
    int page = 1,
    int pageSize = playlistMaxPageSize,
  }) async {
    final json = await _getObject('/api/playlist/get-playlist-works', {
      'id': playlistId,
      'page': '$page',
      'pageSize': '${clampPlaylistPageSize(pageSize)}',
    });
    return PlaylistWorkPage.fromJson(json);
  }

  /// 某作品在「我的歌单」中的分布（`GET /api/playlist/get-work-exist-status-in-my-playlists`）。
  ///
  /// 返回的每个歌单都带 `exist`（bool），正好喂给多选菜单做预勾选。
  /// **按页返回**，歌单多于一页时预勾选会漏 → 这里自己翻页到覆盖 `totalCount` 为止。
  ///
  /// 1.93.1 前这里默认 `pageSize = 200`，被服务端 400 拒掉；调用方（多选菜单）
  /// 把异常吞了，于是「权威勾选」一直是静默失效的 —— 现在改为翻页覆盖。
  Future<List<OnlinePlaylist>> fetchWorkPlaylistStatus(
    int workId, {
    int pageSize = playlistMaxPageSize,
  }) async {
    final size = clampPlaylistPageSize(pageSize);
    final out = <OnlinePlaylist>[];
    for (var page = 1; page <= _maxStatusPages; page++) {
      final json = await _getObject(
        '/api/playlist/get-work-exist-status-in-my-playlists',
        {
          'workID': '$workId',
          'page': '$page',
          'pageSize': '$size',
          'version': '2',
        },
      );
      final parsed = OnlinePlaylistPage.fromJson(json);
      out.addAll(parsed.playlists);
      if (parsed.playlists.isEmpty || out.length >= parsed.totalCount) break;
    }
    return out;
  }

  /// 新建歌单（`POST /api/playlist/create-playlist`）。
  /// [works] 传 **source_id 字符串**列表（`RJ01657200`）；不传就是空歌单。
  Future<OnlinePlaylist> createPlaylist({
    required String name,
    int privacy = OnlinePlaylist.defaultPrivacy,
    List<String> works = const [],
    String description = '',
    String locale = 'zh-CN',
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw KikoeruException('歌单名不能为空');
    final json = await _postJson('/api/playlist/create-playlist', {
      'name': trimmed,
      'privacy': privacy,
      'locale': locale,
      'description': description,
      if (works.isNotEmpty) 'works': works,
    });
    if (json is! Map) throw KikoeruException('服务器没有返回新建的歌单');
    return OnlinePlaylist.fromJson(Map<String, dynamic>.from(json));
  }

  /// 改名 / 改隐私 / 改描述（`POST /api/playlist/edit-playlist-metadata`）。
  /// 系统保留歌单会被服务端拒绝（Hiko 侧靠 `OnlinePlaylist.editable` 提前收口）。
  Future<OnlinePlaylist> editPlaylistMetadata(
    String playlistId, {
    String? name,
    int? privacy,
    String? description,
  }) async {
    final trimmed = name?.trim();
    if (name != null && (trimmed == null || trimmed.isEmpty)) {
      throw KikoeruException('歌单名不能为空');
    }
    // 只发改动过的字段：服务端对缺失字段保持原值
    final data = <String, Object>{};
    if (trimmed != null) data['name'] = trimmed;
    if (privacy != null) data['privacy'] = privacy;
    if (description != null) data['description'] = description;
    final json = await _postJson('/api/playlist/edit-playlist-metadata', {
      'id': playlistId,
      'data': data,
    });
    if (json is! Map) throw KikoeruException('服务器没有返回修改后的歌单');
    return OnlinePlaylist.fromJson(Map<String, dynamic>.from(json));
  }

  /// 删除歌单（`POST /api/playlist/delete-playlist`）。**歌单内的作品不受影响**。
  Future<void> deletePlaylist(String playlistId) async {
    await _postVoid('/api/playlist/delete-playlist', {'id': playlistId});
  }

  /// 把作品加进歌单（`POST /api/playlist/add-works-to-playlist`），返回受影响行数。
  /// [workIds] 必须是**数字 work id**（不是 `RJ…`）。
  Future<int> addWorksToPlaylist(String playlistId, List<int> workIds) async {
    if (workIds.isEmpty) return 0;
    final json = await _postJson('/api/playlist/add-works-to-playlist', {
      'id': playlistId,
      'works': workIds,
    });
    return json is Map ? (json['rowCount'] as num?)?.toInt() ?? 0 : 0;
  }

  /// 把作品移出歌单（`POST /api/playlist/remove-works-from-playlist`），返回受影响行数。
  /// 同样只吃**数字 work id**。
  Future<int> removeWorksFromPlaylist(
    String playlistId,
    List<int> workIds,
  ) async {
    if (workIds.isEmpty) return 0;
    final json = await _postJson('/api/playlist/remove-works-from-playlist', {
      'id': playlistId,
      'works': workIds,
    });
    return json is Map ? (json['rowCount'] as num?)?.toInt() ?? 0 : 0;
  }

  // ------------------------------------------------------------ URL 构造

  /// 封面地址。[size] 传 [coverMainSize] 取原图（列表与详情都用它），
  /// null 等价于原图；[coverThumbSize] 只在明确需要小图时用（如后台缩略图）。
  ///
  /// 原始封面是 560×420（约 58–98 KB）。用 240×180 的缩略图放大到卡片尺寸
  /// 就是 1.93.0 修掉的那个模糊问题，见 [coverThumbSize] 的注释。
  String coverUrl(int workId, {String? size}) {
    final suffix = size == null ? '' : '?type=$size';
    return '$baseUrl/api/cover/$workId.jpg$suffix';
  }

  /// **应用里展示封面一律走这个**（列表卡片 / 详情大图 / 环境背板 / 正在播放）。
  ///
  /// 单独开一个出口的理由有两个：
  /// ① 1.93.0 修的封面模糊是「某处又悄悄传了缩略图尺寸」这一类错误 ——
  ///    所有调用点共用一个函数，才有一个地方可以钉回归测试；
  /// ② 同一个作品在列表和详情里用的是**同一个 URL 字符串**，于是封面磁盘缓存
  ///    只存一份、详情页能直接命中列表已经下好的图。
  String coverMainUrl(int workId) => coverUrl(workId, size: coverMainSize);

  /// 音频流入口。返回 302 到 CDN 直链，交由播放器跟随重定向。
  ///
  /// 刻意不用曲目树里的 `mediaStreamUrl` 裸直链：那是 CDN 内部地址，
  /// 不带签名时可以过但**没有稳定性承诺**；走 `/api/media/stream/` 由服务端
  /// 每次签发新的时效签名，是唯一有契约保障的入口。
  String streamUrl(String hash) => '$baseUrl/api/media/stream/$hash';

  /// 从媒体流 URL 反解服务端 hash（供缓存与字幕配对使用）：
  /// `https://api.asmr.one/api/media/stream/1657200/1937305` → `1657200/1937305`
  static String? hashFromStreamUrl(String url) {
    const marker = '/api/media/stream/';
    final index = url.indexOf(marker);
    if (index < 0) return null;
    final hash = url.substring(index + marker.length);
    return hash.isEmpty ? null : hash;
  }

  /// 从**播放 URL** 反解服务端 hash，两种形态都吃：
  /// - 走流播时的 `https://…/api/media/stream/1657200/1937305`
  /// - 命中磁盘缓存时的 `file:///…/1657200_1937305.mp3`（文件名约定见 [OnlineAudioCache]）
  ///
  /// 详情页据它判断「当前播放的是不是我这一行」，比按数组下标比对可靠 ——
  /// 在线有「整部作品 / 单个目录 / 单个叶子目录」三种播放范围，下标互不对齐。
  static String? hashFromPlaybackUrl(String url) {
    if (!url.startsWith('file:')) return hashFromStreamUrl(url);
    final name = Uri.parse(url).pathSegments.last;
    final stem =
        name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final sep = stem.indexOf('_');
    if (sep <= 0) return null;
    return '${stem.substring(0, sep)}/${stem.substring(sep + 1)}';
  }

  /// 作品页地址（「在浏览器打开」用）。
  ///
  /// 注意官方实例的 API 域名不是网页域名（`https://api.asmr.one/works/{id}` 实测 404），
  /// 由 [onlineWorkPageUrl] 统一映射到 `www.asmr.one`。
  String workPageUrl(int workId) => onlineWorkPageUrl(baseUrl, workId);

  // -------------------------------------------------------------- 内部

  /// 拍平服务端的嵌套文件树（folder 只用于分组与字幕配对）
  static void _flatten(List nodes, String parentPath, List<OnlineTrack> out) {
    for (final node in nodes) {
      if (node is! Map) continue;
      final map = Map<String, dynamic>.from(node);
      final type = (map['type'] as String?) ?? '';
      final title = (map['title'] as String?) ?? '';
      if (type == 'folder') {
        final children = map['children'];
        if (children is List) {
          _flatten(children, parentPath.isEmpty ? title : '$parentPath/$title', out);
        }
        continue;
      }
      final hash = map['hash'];
      if (hash is! String || hash.isEmpty) continue;
      out.add(OnlineTrack(
        hash: hash,
        title: title,
        type: type,
        size: (map['size'] as num?)?.toInt() ?? 0,
        duration: (map['duration'] as num?)?.toDouble() ?? 0,
        mediaStreamUrl: map['mediaStreamUrl'] as String?,
        relativePath: parentPath,
      ));
    }
  }

  /// 字幕配对：把同目录下的文本文件挂到同名音轨上（作品自带 LRC/VTT）
  static List<OnlineTrack> _attachLyrics(List<OnlineTrack> files) {
    final texts = files.where((f) => f.isText).toList();
    if (texts.isEmpty) return files;
    return [
      for (final f in files)
        if (!f.isAudio)
          f
        else
          switch (_matchLyric(f, texts)) {
            final OnlineTrack lyric =>
              f.copyWith(lyricsHash: lyric.hash, lyricsTitle: lyric.title),
            null => f,
          },
    ];
  }

  static final _lyricExts = RegExp(
    r'\.(lrc|vtt|srt|ass|ssa|sub|sbv|dfxp|ttml)$',
    caseSensitive: false,
  );

  static OnlineTrack? _matchLyric(OnlineTrack audio, List<OnlineTrack> texts) {
    final audioName = audio.title.toLowerCase();
    final audioStem = _stem(audioName);
    for (final t in texts) {
      if (t.relativePath != audio.relativePath) continue;
      final tName = t.title.toLowerCase();
      final tStem = _stem(tName);
      // 同名（01.mp3 → 01.lrc）、双扩展名（01.mp3.lrc）、stem 相同（01.mp3 → 01.lrc）
      if (tStem == audioStem || tStem == audioName || tName == '$audioName.lrc') {
        return t;
      }
      if (tName.startsWith(audioName) && _isLyricExt(tName)) return t;
    }
    return null;
  }

  static bool _isLyricExt(String name) => _lyricExts.hasMatch(name);

  /// 去扩展名；`.mp3` / `.lrc` 皆可，无扩展名原样返回
  static String _stem(String name) {
    final base = p.basename(name).toLowerCase();
    if (!base.contains('.')) return base;
    return p.basenameWithoutExtension(base);
  }

  Future<dynamic> _getDecoded(String path, [Map<String, String>? query]) async {
    final text = await _request(path, query);
    return _decode(text);
  }

  Future<Map<String, dynamic>> _getObject(
      String path, [Map<String, String>? query]) async {
    final decoded = await _getDecoded(path, query);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw KikoeruException('服务器返回的内容格式异常');
  }

  /// POST 一个 JSON 体并解析响应（返回 null 表示响应体为空）
  Future<dynamic> _postJson(String path, Object body) async {
    final text = await _request(path, null, method: 'POST', body: body);
    if (text.trim().isEmpty) return null;
    return _decode(text);
  }

  /// POST 一个 JSON 体，只要状态码成功（删除等无返回值的端点）
  Future<void> _postVoid(String path, Object body) async {
    await _request(path, null, method: 'POST', body: body);
  }

  static dynamic _decode(String text) {
    try {
      return jsonDecode(text);
    } catch (e) {
      throw KikoeruException('服务器返回的内容无法解析', e);
    }
  }

  /// 遍历候选地址请求；网络级失败换下一个镜像，业务级错误（4xx/5xx）直接抛出。
  ///
  /// **[method] 为 POST 时不做镜像回退**：网络超时意味着「请求可能已经落到服务端
  /// 但响应没回来」，此时换镜像重发可能造成重复写入（比如建出两个同名歌单）。
  /// 宁可报错让用户重试 —— 而且在这之前至少有一次 GET 已经解析出可用的
  /// `_activeBase`，所以打不通的情况本就很罕见。
  Future<String> _request(
    String path,
    Map<String, String>? query, {
    String method = 'GET',
    Object? body,
  }) async {
    final isMutation = method != 'GET';
    final candidates = isMutation ? [baseUrl] : _candidates;
    Object? lastError;
    for (final base in candidates) {
      final uri = query == null || query.isEmpty
          ? Uri.parse('$base$path')
          : Uri.parse('$base$path').replace(queryParameters: query);
      try {
        final response = await _send(uri, method: method, body: body);
        _activeBase = base;
        return response;
      } on KikoeruException {
        rethrow; // HTTP 状态码错误换镜像也没用（同一个服务端逻辑）
      } catch (e) {
        lastError = e; // 连接超时 / DNS / 拒绝连接 → 试下一个镜像
      }
    }
    throw KikoeruException('无法连接在线服务器，请检查网络或服务器地址', lastError);
  }

  Future<String> _getString(Uri uri) => _send(uri, method: 'GET');

  /// 发一个请求。[body] 非空时以 JSON 形式提交。
  ///
  /// 错误响应体会被读出来解析成可读文案 —— asmr.one 的错误一律是
  /// `{"error":"用户名或密码错误."}` 这种中文原句，比「服务器返回 401」有用得多。
  Future<String> _send(
    Uri uri, {
    String method = 'GET',
    Object? body,
  }) async {
    final client = _newClient();
    try {
      final request = await (method == 'POST'
              ? client.postUrl(uri)
              : client.getUrl(uri))
          .timeout(_timeout);
      if (isOfficial) {
        // 防御性伪装：官方实例前置 Cloudflare，浏览器 UA/Referer 更稳
        request.headers.set(HttpHeaders.userAgentHeader, _browserUa);
        request.headers.set(HttpHeaders.refererHeader, 'https://www.asmr.one/');
      } else {
        request.headers.set(HttpHeaders.userAgentHeader, 'Hiko');
      }
      if (authenticated) {
        // asmr.one 网页端就是这么发的（interceptors/request.js）：
        // `Authorization: Bearer ${localStorage['jwt-token']}`
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $token',
        );
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(_timeout);
      final text = await response.transform(utf8.decoder).join().timeout(_timeout);
      if (response.statusCode >= 400) {
        throw KikoeruException(
          _describeHttpError(response.statusCode, text),
          null,
          response.statusCode,
        );
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  /// 错误响应文案：优先透出服务端原句，取不到再退回状态码
  static String _describeHttpError(int status, String body) {
    final detail = parseServerError(body);
    if (detail != null) return detail;
    return switch (status) {
      401 => '登录已过期，请重新登录',
      403 => '没有权限执行该操作（服务器返回 403）',
      404 => '服务器上找不到该资源（404）',
      _ => '服务器返回 $status',
    };
  }

  /// 从服务端错误体里抽出可读文案。三种形态都吃（实测）：
  /// - `{"error":"用户名或密码错误."}`（鉴权类）
  /// - `{"errors":[{"value":"RJ01…","msg":"Invalid value",…}]}`（express-validator）
  /// - `{"message":"…"}`
  static String? parseServerError(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map) {
          final msg = first['msg'];
          if (msg is String && msg.trim().isNotEmpty) {
            final param = first['param'];
            return param is String && param.isNotEmpty ? '$msg（$param）' : msg;
          }
        }
      }
      final message = decoded['message'];
      if (message is String && message.trim().isNotEmpty) return message.trim();
    } catch (_) {
      // 非 JSON 错误体（网关的 HTML 错误页等），交给状态码兜底
    }
    return null;
  }

  static const _browserUa =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';

  /// 每次请求新建 client（复用会阻塞于长连接；在线浏览是低频短请求）
  HttpClient _newClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 5);
    final proxyValue = proxy.trim();
    if (proxyValue.isNotEmpty) {
      final uri = Uri.tryParse(
          proxyValue.contains('://') ? proxyValue : 'http://$proxyValue');
      if (uri != null && uri.host.isNotEmpty) {
        client.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
      }
    }
    return client;
  }
}
