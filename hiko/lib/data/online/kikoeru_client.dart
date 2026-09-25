import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'online_models.dart';

/// 在线请求异常（含可展示的中文说明）
class KikoeruException implements Exception {
  KikoeruException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message（$cause）';
}

/// Kikoeru 兼容服务器的 HTTP 客户端（asmr.one 即该协议的公共实例）。
///
/// 实测确认的关键点（2026-09-25，见 .workbuddy/memory/2026-09-25.md）：
/// - **浏览/搜索/详情/曲目树/封面/字幕/音频流全部匿名可用**，无需 token；
///   需要登录的只有收藏、评分、进度同步等写操作，本客户端不涉及。
/// - 端点是**单数**形式：`/api/work/{id}`、`/api/tracks/{id}`；
///   复数形式 `/api/works/{id}` 会返回 401，不要混用。
/// - 音频流 `/api/media/stream/{hash}` 返回 302 跳转到带时效签名的 CDN 直链，
///   播放器跟随重定向即可，支持 Range。
/// - 官方实例有 4 个镜像域名，任一可用即可；自建服务器不做镜像回退。
class KikoeruClient {
  KikoeruClient({required String baseUrl, this.proxy = '', Duration? timeout})
      : _configuredBase = normalizeBase(baseUrl),
        _timeout = timeout ?? const Duration(seconds: 20);

  /// 官网镜像族（仅当地址属于该族时才启用回退，自建服务器绝不跨站重试）
  static const officialMirrors = <String>[
    'https://api.asmr.one',
    'https://api.asmr-200.com',
    'https://api.asmr-100.com',
    'https://api.asmr-300.com',
  ];

  /// 列表默认取 20 条/页：封面走 240x240 缩略图，滚动时不至于一次拉太多
  static const defaultPageSize = 20;

  /// 播放器展示用的封面尺寸
  static const coverThumbSize = '240x240';

  final String _configuredBase;
  final String proxy;
  final Duration _timeout;

  /// 会话内记住的可用地址（镜像回退命中后不再每次重试坏地址）
  String? _activeBase;

  String get baseUrl => _activeBase ?? _configuredBase;
  String get configuredBase => _configuredBase;
  bool get isOfficial => _configuredBase.contains('api.asmr');

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

  /// 作品列表（`GET /api/works`）
  Future<OnlineWorkPage> fetchWorks({
    int page = 1,
    int pageSize = defaultPageSize,
    OnlineOrder order = OnlineOrder.createDate,
    bool desc = true,
    bool subtitleOnly = false,
  }) async {
    final json = await _getObject('/api/works', {
      'page': '$page',
      'pageSize': '$pageSize',
      'order': order.key,
      'sort': desc ? 'desc' : 'asc',
      if (subtitleOnly) 'subtitle': '1',
    });
    return OnlineWorkPage.fromJson(json);
  }

  /// 关键词搜索（`GET /api/search/{keyword}`，支持与列表相同的分页/排序参数）
  Future<OnlineWorkPage> searchWorks(
    String keyword, {
    int page = 1,
    int pageSize = defaultPageSize,
    OnlineOrder order = OnlineOrder.createDate,
    bool desc = true,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      return const OnlineWorkPage(
          works: [], currentPage: 1, pageSize: 0, totalCount: 0);
    }
    final json = await _getObject('/api/search/${Uri.encodeComponent(kw)}', {
      'page': '$page',
      'pageSize': '$pageSize',
      'order': order.key,
      'sort': desc ? 'desc' : 'asc',
    });
    return OnlineWorkPage.fromJson(json);
  }

  /// 按标签筛选（`GET /api/tags/{tagId}/works`）
  Future<OnlineWorkPage> fetchWorksByTag(
    int tagId, {
    int page = 1,
    int pageSize = defaultPageSize,
    OnlineOrder order = OnlineOrder.dlCount,
  }) async {
    final json = await _getObject('/api/tags/$tagId/works', {
      'page': '$page',
      'pageSize': '$pageSize',
      'order': order.key,
      'sort': 'desc',
    });
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

  /// 解析服务端嵌套曲目树：拍平成一维文件列表 + 字幕配对（纯函数，单测覆盖）
  static List<OnlineTrack> parseTrackTree(List nodes) {
    final files = <OnlineTrack>[];
    _flatten(nodes, '', files);
    return _attachLyrics(files);
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

  // ------------------------------------------------------------ URL 构造

  /// 封面地址。[size] 传 [coverThumbSize] 取缩略图（列表用），null 取原图（详情用）
  String coverUrl(int workId, {String? size}) {
    final suffix = size == null ? '' : '?type=$size';
    return '$baseUrl/api/cover/$workId.jpg$suffix';
  }

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

  /// 作品页地址（「在浏览器打开」用）
  String workPageUrl(int workId) => '$baseUrl/works/$workId';

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
    try {
      return jsonDecode(text);
    } catch (e) {
      throw KikoeruException('服务器返回的内容无法解析', e);
    }
  }

  Future<Map<String, dynamic>> _getObject(
      String path, [Map<String, String>? query]) async {
    final decoded = await _getDecoded(path, query);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw KikoeruException('服务器返回的内容格式异常');
  }

  /// 遍历候选地址请求；网络级失败换下一个镜像，业务级错误（4xx/5xx）直接抛出
  Future<String> _request(String path, Map<String, String>? query) async {
    Object? lastError;
    for (final base in _candidates) {
      final uri = query == null || query.isEmpty
          ? Uri.parse('$base$path')
          : Uri.parse('$base$path').replace(queryParameters: query);
      try {
        final body = await _getString(uri);
        _activeBase = base;
        return body;
      } on KikoeruException {
        rethrow; // HTTP 状态码错误换镜像也没用（同一个服务端逻辑）
      } catch (e) {
        lastError = e; // 连接超时 / DNS / 拒绝连接 → 试下一个镜像
      }
    }
    throw KikoeruException('无法连接在线服务器，请检查网络或服务器地址', lastError);
  }

  Future<String> _getString(Uri uri) async {
    final client = _newClient();
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      if (isOfficial) {
        // 防御性伪装：官方实例前置 Cloudflare，浏览器 UA/Referer 更稳
        request.headers.set(HttpHeaders.userAgentHeader, _browserUa);
        request.headers.set(HttpHeaders.refererHeader, 'https://www.asmr.one/');
      } else {
        request.headers.set(HttpHeaders.userAgentHeader, 'Hiko');
      }
      final response = await request.close().timeout(_timeout);
      if (response.statusCode >= 400) {
        await response.drain<void>();
        throw KikoeruException('服务器返回 ${response.statusCode}');
      }
      return await response.transform(utf8.decoder).join().timeout(_timeout);
    } finally {
      client.close(force: true);
    }
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
