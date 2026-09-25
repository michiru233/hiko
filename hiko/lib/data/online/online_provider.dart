import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lyrics/lyrics_controller.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../playback/playback_controller.dart';
import '../settings_store.dart';
import 'kikoeru_client.dart';
import 'online_audio_cache.dart';
import 'online_models.dart';

/// 在线服务客户端（服务器地址或代理变化时重建）
final onlineClientProvider = Provider<KikoeruClient>((ref) {
  final server = ref.watch(settingsProvider.select((s) => s.onlineServer));
  final proxy = ref.watch(settingsProvider.select((s) => s.scrapeProxy));
  return KikoeruClient(baseUrl: server, proxy: proxy);
});

/// 在线音频磁盘缓存（上限随设置变化重建；0 GB 表示完全关闭缓存）
final onlineAudioCacheProvider = Provider<OnlineAudioCache>((ref) {
  final limitGb =
      ref.watch(settingsProvider.select((s) => s.onlineCacheLimitGb));
  final cache = OnlineAudioCache(
    limitBytes: (limitGb * 1024 * 1024 * 1024).round(),
  );
  unawaited(cache.init());
  return cache;
});

/// 在线浏览入口
enum OnlineFeed {
  popular('热门', '按下载量排序'),
  latest('最新', '按发售日期排序'),
  search('搜索', '关键词搜索'),
  tag('标签', '按标签筛选');

  const OnlineFeed(this.label, this.description);

  final String label;
  final String description;
}

@immutable
class OnlineBrowseState {
  const OnlineBrowseState({
    this.feed = OnlineFeed.popular,
    this.keyword = '',
    this.tag,
    this.order = OnlineOrder.dlCount,
    this.descending = true,
    this.subtitleOnly = false,
    this.works = const [],
    this.totalCount = 0,
    this.page = 1,
    this.pageSize = KikoeruClient.defaultPageSize,
    this.loading = false,
    this.error,
  });

  final OnlineFeed feed;
  final String keyword;
  final OnlineTag? tag;
  final OnlineOrder order;
  final bool descending;
  final bool subtitleOnly;

  /// 当前页的作品（1.91.0 起为整页替换，不再跨页累加）
  final List<OnlineWork> works;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool loading;
  final String? error;

  int get totalPages =>
      pageSize <= 0 ? 0 : (totalCount + pageSize - 1) ~/ pageSize;
  bool get hasPrev => page > 1;
  bool get hasNext => page < totalPages;
  bool get isEmpty => !loading && works.isEmpty;

  OnlineBrowseState copyWith({
    OnlineFeed? feed,
    String? keyword,
    OnlineTag? tag,
    bool clearTag = false,
    OnlineOrder? order,
    bool? descending,
    bool? subtitleOnly,
    List<OnlineWork>? works,
    int? totalCount,
    int? page,
    int? pageSize,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      OnlineBrowseState(
        feed: feed ?? this.feed,
        keyword: keyword ?? this.keyword,
        tag: clearTag ? null : (tag ?? this.tag),
        order: order ?? this.order,
        descending: descending ?? this.descending,
        subtitleOnly: subtitleOnly ?? this.subtitleOnly,
        works: works ?? this.works,
        totalCount: totalCount ?? this.totalCount,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 在线浏览控制器：热门 / 最新 / 搜索 / 标签筛选 + 翻页
class OnlineBrowseNotifier extends StateNotifier<OnlineBrowseState> {
  OnlineBrowseNotifier(this._ref) : super(const OnlineBrowseState());

  final Ref _ref;

  /// 每页条数档位。实测服务端 pageSize 到 500 都能正常返回；
  /// 全站 6 万余件，20 条/页要翻 3000 多页，所以提供更大档位。
  static const pageSizeOptions = <int>[20, 60, 100];

  Future<void> loadFeed(OnlineFeed feed) async {
    state = state.copyWith(
      feed: feed,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
      clearTag: feed != OnlineFeed.tag,
      order: switch (feed) {
        OnlineFeed.popular => OnlineOrder.dlCount,
        OnlineFeed.latest => OnlineOrder.release,
        OnlineFeed.search => state.order,
        OnlineFeed.tag => OnlineOrder.dlCount,
      },
    );
    await _fetch(1);
  }

  Future<void> search(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    state = state.copyWith(
      feed: OnlineFeed.search,
      keyword: kw,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  Future<void> selectTag(OnlineTag tag) async {
    state = state.copyWith(
      feed: OnlineFeed.tag,
      tag: tag,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  /// 切换排序维度（再次选同一维度则反转升降序）
  Future<void> setOrder(OnlineOrder order) async {
    if (state.feed == OnlineFeed.popular || state.feed == OnlineFeed.latest) {
      return; // 这两个入口的排序语义固定，不参与自定义排序
    }
    final same = state.order == order;
    state = state.copyWith(
      order: order,
      descending: same ? !state.descending : true,
      works: const [],
      page: 1,
      loading: true,
    );
    await _fetch(1);
  }

  /// 只看带字幕的作品（仅热门/最新入口生效）
  Future<void> toggleSubtitleOnly() async {
    if (state.feed != OnlineFeed.popular && state.feed != OnlineFeed.latest) {
      return;
    }
    state = state.copyWith(
      subtitleOnly: !state.subtitleOnly,
      works: const [],
      page: 1,
      loading: true,
    );
    await _fetch(1);
  }

  Future<void> refresh() => _fetch(state.page);

  /// 跳到指定页（越界自动夹到有效范围）
  Future<void> goToPage(int page) async {
    if (state.loading || state.totalPages <= 0) return;
    final target = page.clamp(1, state.totalPages);
    if (target == state.page && state.works.isNotEmpty) return;
    state = state.copyWith(loading: true, clearError: true);
    await _fetch(target);
  }

  /// 切换每页条数：回到第 1 页（保持行号语义简单，不做页码换算）
  Future<void> setPageSize(int size) async {
    if (size == state.pageSize || !pageSizeOptions.contains(size)) return;
    state = state.copyWith(
      pageSize: size,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  Future<void> _fetch(int page) async {
    final client = _ref.read(onlineClientProvider);
    final size = state.pageSize;
    try {
      final result = await switch (state.feed) {
        OnlineFeed.popular => client.fetchWorks(
            page: page,
            pageSize: size,
            order: OnlineOrder.dlCount,
            subtitleOnly: state.subtitleOnly,
          ),
        OnlineFeed.latest => client.fetchWorks(
            page: page,
            pageSize: size,
            order: OnlineOrder.release,
            subtitleOnly: state.subtitleOnly,
          ),
        OnlineFeed.search => client.searchWorks(
            state.keyword,
            page: page,
            pageSize: size,
            order: state.order,
            desc: state.descending,
          ),
        OnlineFeed.tag => client.fetchWorksByTag(
            state.tag?.id ?? 0,
            page: page,
            pageSize: size,
            order: state.order,
          ),
      };
      if (!mounted) return;
      state = state.copyWith(
        works: result.works,
        totalCount: result.totalCount,
        page: page,
        loading: false,
        clearError: true,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        loading: false,
        error: _describeError(e),
      );
    }
  }

  static String _describeError(Object e) {
    final text = e is KikoeruException ? e.message : '$e';
    return '加载失败：$text';
  }
}

final onlineBrowseProvider =
    StateNotifierProvider<OnlineBrowseNotifier, OnlineBrowseState>(
  (ref) => OnlineBrowseNotifier(ref),
);

/// 标签表（懒加载 + 会话内缓存，422 个约 72KB）
final onlineTagsProvider = FutureProvider<List<OnlineTag>>((ref) async {
  return ref.watch(onlineClientProvider).fetchTags();
});

/// 作品详情：作品元数据 + 曲目树（两个请求并发）
@immutable
class OnlineDetail {
  const OnlineDetail({
    required this.work,
    required this.tracks,
    this.tree = const [],
  });

  final OnlineWork work;

  /// 拍平后的全部文件（含字幕/图片），保持服务端顺序 —— 播放序与字幕配对的依据
  final List<OnlineTrack> tracks;

  /// 还原的目录层级（详情页按 asmr.one 分组展示用），不限深度
  final List<OnlineNode> tree;

  List<OnlineTrack> get audioTracks =>
      tracks.where((t) => t.playable).toList();

  /// 某曲所属的「组」= 同一叶子目录内的可播放曲目。
  ///
  /// 这是点单曲时的接续范围（裁决 Q5=C）：同一个 `02：wav` 目录里的下一首，
  /// 而不是跨到 `01：mp3` 或英语版去。目录路径由 [OnlineTrack.relativePath] 表达，
  /// 所以不需要遍历节点树。
  List<OnlineTrack> groupOf(OnlineTrack track) =>
      audioTracks.where((t) => t.relativePath == track.relativePath).toList();

  bool get hasLyrics => tracks.any((t) => t.lyricsHash != null);
  bool get canPlay => tracks.any((t) => t.playable);
}

final onlineDetailProvider =
    FutureProvider.family<OnlineDetail, int>((ref, workId) async {
  final client = ref.watch(onlineClientProvider);
  final workFuture = client.fetchWork(workId);
  final bundle = await client.fetchTrackTree(workId);
  final detailWork = await workFuture;
  return OnlineDetail(
    work: detailWork,
    tracks: bundle.tracks,
    tree: bundle.tree,
  );
});

/// 在线播放协调器：把在线作品变成内存态 Album 交给现有播放器，
/// 并负责异步字幕补齐与后台缓存落盘。
///
/// 刻意不写入 library.json —— 在线专辑的 id 前缀为 `online-`，
/// `PlaybackController` 据此跳过库进度落盘，本地库清理逻辑也不受影响。
class OnlinePlayback {
  OnlinePlayback(this._ref) {
    _ref.listen<PlaybackState>(playbackProvider, _onPlaybackChanged);
  }

  final Ref _ref;

  /// 播放达到该秒数后才启动后台缓存下载：避免「点开就退出」白耗流量
  static const cacheTriggerSeconds = 20.0;

  /// 曲目 hash → 文件大小（曲目树提供，用于下载完整性校验）
  final _sizeIndex = <String, int>{};

  /// 音轨 URL → 待补拉的字幕 hash（曲目切换后异步补齐歌词用）
  final _lyricsIndex = <String, String>{};

  /// 当前在线浏览列表，供「专辑循环」跨作品接续时定位相邻作品
  List<OnlineWork> _queue = const [];

  /// 播放某个在线作品。[tracks] 由详情页传入，避免重复请求曲目树。
  /// 返回错误提示文案，null 表示已开始播放。
  Future<String?> play(
    OnlineWork work,
    List<OnlineTrack> tracks, {
    int startIndex = 0,
    List<OnlineWork>? queue,
  }) async {
    final audio = tracks.where((t) => t.playable).toList();
    if (audio.isEmpty) return '这个作品没有可播放的音轨';

    if (queue != null && queue.isNotEmpty) {
      _queue = queue;
      _installOnlineAdvance();
    }

    final album = await buildAlbum(work, audio, startIndex: startIndex);
    final index = startIndex.clamp(0, audio.length - 1);
    await _ref.read(playbackProvider.notifier).playAlbum(album, index: index);
    return null;
  }

  /// 把在线作品构造成可播放的内存态 [Album]。
  ///
  /// 起播曲的字幕同步拉取（单个小请求，确保首屏歌词即时可用），
  /// 其余曲目的字幕与音频缓存都在后台补齐。
  Future<Album> buildAlbum(
    OnlineWork work,
    List<OnlineTrack> audio, {
    int startIndex = 0,
  }) async {
    final client = _ref.read(onlineClientProvider);
    final cache = _ref.read(onlineAudioCacheProvider);

    final tracks = <Track>[];
    for (var i = 0; i < audio.length; i++) {
      final item = audio[i];
      _sizeIndex[item.hash] = item.size;
      if (item.lyricsHash != null) _lyricsIndex[item.hash] = item.lyricsHash!;

      // 缓存命中走本地文件（零流量、可离线重播），否则走服务端流并后台落盘
      final cachedPath = cache.cachedPath(item.hash);
      final url = cachedPath != null
          ? Uri.file(cachedPath).toString()
          : client.streamUrl(item.hash);
      if (cachedPath != null) unawaited(cache.touch(item.hash));

      tracks.add(Track(index: i, name: _displayName(item.title), url: url));
    }

    final index = startIndex.clamp(0, audio.length - 1);
    if (audio[index].lyricsHash != null) {
      final text = await client.fetchText(audio[index].lyricsHash!);
      if (text != null) tracks[index].lyricsText = text;
    }
    unawaited(_fillLyricsLazily(client, audio, tracks, skipIndex: index));

    return Album(
      id: work.albumId,
      sourcePath: OnlineWork.sourcePathFor(work.id),
      title: work.title,
      artist: work.vas.isNotEmpty ? work.vas.join('・') : '在线作品',
      albumArtist: work.circleName,
      rjCode: work.rjCode,
      tags: work.tags,
      group: '在线',
      genre: '在线',
      duration: tracks.length,
      date: DateTime.now(),
      tracks: tracks,
      localCover: client.coverUrl(work.id),
    );
  }

  /// 后台补齐其余曲目的字幕，让切歌时歌词已就位。
  /// 分批并发（每批 5 个）：作品可能有几十个音轨，无节制并发会压垮 CDN。
  Future<void> _fillLyricsLazily(
    KikoeruClient client,
    List<OnlineTrack> audio,
    List<Track> tracks, {
    required int skipIndex,
  }) async {
    const batch = 5;
    for (var start = 0; start < audio.length; start += batch) {
      final end = (start + batch).clamp(0, audio.length);
      await Future.wait([
        for (var i = start; i < end; i++)
          if (i != skipIndex && audio[i].lyricsHash != null)
            client.fetchText(audio[i].lyricsHash!).then((text) {
              if (text != null) tracks[i].lyricsText = text;
            }),
      ]);
    }
  }

  void _installOnlineAdvance() {
    _ref.read(playbackProvider.notifier).onlineAdvance = (dir) async {
      final works = _queue;
      if (works.isEmpty) return null;
      final currentId = _ref.read(playbackProvider).album?.id;
      if (currentId == null) return null;
      final i = works.indexWhere((w) => w.albumId == currentId);
      if (i < 0 || works.length <= 1) return null;
      final next = works[(i + dir + works.length) % works.length];
      if (next.albumId == currentId) return null;
      // 按需拉取相邻作品的曲目树（不预取整页，避免点一次播放发几十个请求）
      final tracks = await _ref.read(onlineClientProvider).fetchTracks(next.id);
      final audio = tracks.where((t) => t.playable).toList();
      if (audio.isEmpty) return null;
      return buildAlbum(next, audio, startIndex: 0);
    };
  }

  void _onPlaybackChanged(PlaybackState? previous, PlaybackState next) {
    final album = next.album;
    if (album == null || !album.isOnline) return;
    final track = next.currentTrack;
    if (track == null) return;

    _ensureLyrics(track);
    if (next.position >= cacheTriggerSeconds) {
      _ensureCached(track);
    }
  }

  /// 当前曲目缺歌词但该作品有对应字幕时补拉，并让歌词控制器重新解析一次
  void _ensureLyrics(Track track) {
    if (track.lyricsText != null && track.lyricsText!.trim().isNotEmpty) return;
    final hash = _lyricsIndex[_hashFromUrl(track.url)];
    if (hash == null) return;
    unawaited(() async {
      final text = await _ref.read(onlineClientProvider).fetchText(hash);
      if (text == null || text.trim().isEmpty) return;
      track.lyricsText = text;
      // 曲目已在播放中，歌词控制器不会自行重读，需要显式触发一次
      await _ref.read(lyricsProvider.notifier).reload();
    }());
  }

  void _ensureCached(Track track) {
    if (track.url.startsWith('file:')) return; // 已命中缓存
    final hash = _hashFromUrl(track.url);
    if (hash == null) return;
    final cache = _ref.read(onlineAudioCacheProvider);
    if (cache.limitBytes <= 0) return; // 用户在设置里关掉了缓存
    if (cache.isCached(hash)) return;
    unawaited(cache.download(
      hash,
      Uri.parse(track.url),
      expectedSize: _sizeIndex[hash],
    ));
  }

  /// 从播放 URL 反解 hash（`.../api/media/stream/1657200/1937305`
  /// 或命中缓存时的 `file://…/1657200_1937305.mp3`）
  String? _hashFromUrl(String url) => KikoeruClient.hashFromPlaybackUrl(url);

  /// 音轨标题展示：剥掉扩展名
  static String _displayName(String title) => onlineTrackDisplayName(title);
}

final onlinePlaybackProvider = Provider<OnlinePlayback>(
  (ref) => OnlinePlayback(ref),
);
