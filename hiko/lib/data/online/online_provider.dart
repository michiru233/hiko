import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lyrics/lyrics_controller.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../playback/playback_controller.dart';
import '../settings_store.dart';
import 'kikoeru_client.dart';
import 'online_account.dart';
import 'online_audio_cache.dart';
import 'online_blacklist.dart';
import 'online_models.dart';

/// 在线服务客户端（服务器地址、代理或登录令牌变化时重建）
///
/// 令牌挂在客户端上而不是每次调用现取：歌单那批端点**必须**带
/// `Authorization: Bearer`，而 client 是无状态短请求的发起方，
/// 令牌变化时重建一个即可，不必每个调用点自己拼头。
final onlineClientProvider = Provider<KikoeruClient>((ref) {
  final server = ref.watch(settingsProvider.select((s) => s.onlineServer));
  final proxy = ref.watch(settingsProvider.select((s) => s.scrapeProxy));
  final token = ref.watch(onlineAccountProvider.select((s) => s.token));
  return KikoeruClient(baseUrl: server, proxy: proxy, token: token);
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

/// 在线浏览的**数据来源**：决定请求哪个端点。
///
/// 1.92.0 起与排序彻底解耦（裁决 Q8=A）。「热门」「最新」不再是来源 ——
/// 它们只是 [OnlineSort] 的两个预设，数据都走 [browse] 这条 `/api/works`。
/// 旧的 `OnlineFeed` 把「榜单」和「排序」搅在一起，于是「热门榜按价格排序」
/// 这种自相矛盾的状态在类型上就是可表达的。
enum OnlineSource {
  /// 无关键词、无标签的全站浏览（`/api/works`）
  browse,
  search,
  tag,
}

/// 声优 / 社团筛选的维度（1.97.0）。
enum OnlineCreatorKind { va, circle }

/// 按声优 / 社团**正向筛选**（1.97.0）。
///
/// 在线作品没有本地播放器那种 artist / albumArtist 标签体系，可筛的 creator
/// 维度只有两个：声优（`vas[].name`）与社团（`circleName`）—— 用户裁决
/// 「艺术家=声优、专辑艺术家=社团，就做这两个」。
///
/// 机制与黑名单同一套：编进搜索关键词（`$va:名$` / `$circle:名$`），
/// 过滤发生在服务端，`totalCount` 与分页天然正确。
/// 只存名字不存 id：语法实测只认名字，与标签同一条纪律。
@immutable
class OnlineCreatorFilter {
  const OnlineCreatorFilter({required this.kind, required this.name});

  final OnlineCreatorKind kind;
  final String name;

  /// 编进关键词的搜索项（`$va:名$` / `$circle:名$`）
  String get term => switch (kind) {
        OnlineCreatorKind.va => vaIncludeTerm(name),
        OnlineCreatorKind.circle => circleIncludeTerm(name),
      };

  /// 标记上的维度名（「声优：某某」/「社团：某某」）
  String get label => kind == OnlineCreatorKind.va ? '声优' : '社团';

  @override
  bool operator ==(Object other) =>
      other is OnlineCreatorFilter &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(kind, name);
}

@immutable
class OnlineBrowseState {
  const OnlineBrowseState({
    this.source = OnlineSource.browse,
    // 冷启动落在热门榜（销量倒序），与旧行为一致
    this.sort = OnlineSort.popularPreset,
    this.keyword = '',
    this.tag,
    this.creator,
    this.subtitleOnly = false,
    this.bypassBlocklist = false,
    this.works = const [],
    this.totalCount = 0,
    this.page = 1,
    this.pageSize = KikoeruClient.defaultPageSize,
    this.loading = false,
    this.error,
  });

  /// 数据从哪来（不影响怎么排）
  final OnlineSource source;

  /// 怎么排（不影响数据从哪来）
  final OnlineSort sort;
  final String keyword;
  final OnlineTag? tag;

  /// 当前生效的声优 / 社团筛选（1.97.0），null = 未启用。
  ///
  /// 与标签筛选同族的正交维度：**翻页、改排序、刷新都保留它**；
  /// 换来源的动作（`applyPreset` / `search` / `selectTag`）清掉它 ——
  /// 对齐 1.94 标签的裁决「看不见的筛选比没有筛选更糟」。
  final OnlineCreatorFilter? creator;
  final bool subtitleOnly;

  /// 这一次标签筛选**放行被屏蔽的标签自己**（1.95.0 裁决 Q5）。
  ///
  /// 只有一条路径会把它置真：用户点了一个已被屏蔽的标签，确认弹窗里选了
  /// 「仍要查看」—— 那是一次明确的、就事论事的例外。所以它**只影响标签来源**，
  /// 且刻意做成「换个来源就自己归零」而不是一个全局开关（Q2 已裁决不做总开关）。
  ///
  /// **只放行当前筛选的那一个标签，不是整份黑名单**：用户说的是「我就要看这一个」，
  /// 把别的屏蔽项一起放出来是替他做了另一个决定。实现见 [_fetch]。
  ///
  /// 翻页 / 改排序**不清它**：清掉会让第 2 页突然少一批作品，用户看到的是
  /// 「同一份筛选、前后页不是一回事」。
  final bool bypassBlocklist;

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

  /// 「只看带字幕」只对全站浏览有意义：它是 `/api/works` 这类列表端点的参数，
  /// 搜索与标签端点没有这个筛选。所以可用性挂**数据来源**，不挂榜单（裁决 Q8=A）。
  /// 声优/社团筛选激活时请求改走搜索接口（`/api/works` 会静默丢弃关键词），
  /// 字幕参数也到不了服务端，所以同样视为不可用。
  bool get canFilterSubtitle =>
      source == OnlineSource.browse && creator == null;

  /// 预设 chip 的高亮判定：**只有当前正好停在该预设上**才亮。
  /// 改了排序就不再属于任何榜单 —— 否则会出现「热门亮着、实际按评价排」的错位。
  /// 声优/社团筛选激活时同理：那已经是「筛选下的排序」，不是榜单本身。
  bool isPresetActive(OnlineSort preset) =>
      source == OnlineSource.browse && creator == null && sort == preset;

  bool get isPopularPreset => isPresetActive(OnlineSort.popularPreset);
  bool get isLatestPreset => isPresetActive(OnlineSort.latestPreset);

  OnlineBrowseState copyWith({
    OnlineSource? source,
    OnlineSort? sort,
    String? keyword,
    OnlineTag? tag,
    bool clearTag = false,
    OnlineCreatorFilter? creator,
    bool clearCreator = false,
    bool? subtitleOnly,
    bool? bypassBlocklist,
    List<OnlineWork>? works,
    int? totalCount,
    int? page,
    int? pageSize,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      OnlineBrowseState(
        source: source ?? this.source,
        sort: sort ?? this.sort,
        keyword: keyword ?? this.keyword,
        tag: clearTag ? null : (tag ?? this.tag),
        creator: clearCreator ? null : (creator ?? this.creator),
        subtitleOnly: subtitleOnly ?? this.subtitleOnly,
        bypassBlocklist: bypassBlocklist ?? this.bypassBlocklist,
        works: works ?? this.works,
        totalCount: totalCount ?? this.totalCount,
        page: page ?? this.page,
        pageSize: pageSize ?? this.pageSize,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 在线浏览控制器：来源（全站浏览 / 搜索 / 标签）× 排序（5 项扁平菜单）× 翻页
class OnlineBrowseNotifier extends StateNotifier<OnlineBrowseState> {
  OnlineBrowseNotifier(this._ref) : super(const OnlineBrowseState()) {
    // 每页条数从设置恢复（1.97.0 起落盘）：设置在应用启动时 load，
    // notifier 首次被 watch 只会晚于那一步。
    final saved = _ref.read(settingsProvider).onlinePageSize.round();
    if (saved != state.pageSize) {
      state = state.copyWith(pageSize: saved);
    }
  }

  final Ref _ref;

  /// 每页条数档位。实测服务端 pageSize 到 500 都能正常返回；
  /// 全站 6 万余件，20 条/页要翻 3000 多页，所以提供更大档位。
  /// 1.97.0 起入口在 设置→在线外观，选择值落盘（`hiko-online-page-size`）。
  static const pageSizeOptions = <int>[20, 60, 100];

  /// 预设入口：热门 / 最新。只切排序，不换数据来源（裁决 Q4=A）。
  Future<void> applyPreset(OnlineSort preset) async {
    if (state.source == OnlineSource.browse &&
        state.sort == preset &&
        state.works.isNotEmpty) {
      return; // 已经停在这个榜上且页面上有数据，点它不该白刷一次
    }
    state = state.copyWith(
      source: OnlineSource.browse,
      sort: preset,
      keyword: '',
      clearTag: true,
      clearCreator: true,
      bypassBlocklist: false,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    // 注意：刻意不清 subtitleOnly —— 它是与来源正交的筛选，切榜不该悄悄关掉它
    await _fetch(1);
  }

  Future<void> search(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    state = state.copyWith(
      source: OnlineSource.search,
      keyword: kw,
      // 离开全站浏览就清掉字幕筛选：搜索/标签下这个 chip 是隐藏的，
      // 留着会让「看不见的筛选」在切回浏览时突然生效
      subtitleOnly: false,
      clearTag: true,
      // 声优/社团筛选同理：新一轮搜索的语义由搜索框决定，
      // 把上一轮的 creator 悄悄叠上去 = 看不见的筛选
      clearCreator: true,
      bypassBlocklist: false,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  /// 按标签筛选。[bypassBlocklist] 只在「点已屏蔽标签 + 用户确认仍要查看」时为真
  /// （1.95.0 裁决 Q5）—— 它让**这一条**筛选临时不叠加黑名单。
  Future<void> selectTag(OnlineTag tag, {bool bypassBlocklist = false}) async {
    state = state.copyWith(
      source: OnlineSource.tag,
      tag: tag,
      subtitleOnly: false,
      keyword: '',
      clearCreator: true,
      bypassBlocklist: bypassBlocklist,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  /// 按声优 / 社团筛选（1.97.0）。
  ///
  /// 与标签筛选同语义的「覆盖式进入」：清字幕筛选、回第 1 页；**保留**当前的
  /// 来源与搜索词 —— 从搜索结果里点开详情再点声优，得到的是「这批关键词 ∩
  /// 这个声优」，而不是突然把用户扔回全站。取消（再点同一个 / 关闭标记）
  /// 由 UI 层走 `applyPreset(latestPreset)`，对齐标签的「取消回最新榜」。
  /// 翻页、改排序、刷新都保留本筛选。
  Future<void> selectCreator(OnlineCreatorFilter filter) async {
    if (state.creator == filter) return;
    state = state.copyWith(
      creator: filter,
      subtitleOnly: false,
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  /// 换排序项：保持当前数据来源与页码语义（回第 1 页），旧结果留在屏上不闪白
  Future<void> setSort(OnlineSort sort) async {
    if (state.sort == sort) return;
    state = state.copyWith(
      sort: sort,
      page: 1,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  /// 只看带字幕（仅全站浏览可用）
  Future<void> toggleSubtitleOnly() async {
    if (!state.canFilterSubtitle) return;
    state = state.copyWith(
      subtitleOnly: !state.subtitleOnly,
      works: const [],
      page: 1,
      loading: true,
    );
    await _fetch(1);
  }

  Future<void> refresh() => _fetch(state.page);

  /// 把某个标签加入黑名单之后的收尾（1.95.0，裁决 Q1=甲：屏蔽要当场可见）。
  ///
  /// 为什么必须重拉：黑名单只是本地状态，服务端的过滤只在**下一次请求**生效。
  /// 只记状态不重拉的话，用户右击「幼なじみ」→ 加入黑名单之后，屏幕上那批作品
  /// 一件都不会消失，直到翻页或换排序才突然变少 —— 看起来像功能没生效。
  ///
  /// [tagId] 正好是**当前筛选的那个标签**时改走「退出筛选、回最新榜」：
  /// 那种请求会变成 `$tag:X$ $-tag:X$`，实测必然是 0 条，留着筛选标记而结果空白
  /// 是自相矛盾的。退出筛选这一点沿用 1.94.0 已定的「取消标签筛选一律回最新榜」。
  Future<void> reloadAfterBlock({required int tagId}) async {
    if (state.source == OnlineSource.tag && state.tag?.id == tagId) {
      await applyPreset(OnlineSort.latestPreset);
      return;
    }
    await _reloadFromFirstPage();
  }

  /// 把某个标签移出黑名单之后的收尾。
  ///
  /// 与 [reloadAfterBlock] 的区别有两处：移出**不会**让标签筛选失效（结果只会变多），
  /// 所以不退出筛选；但要顺手消掉一种残留 —— 之前若正靠「仍要查看」在绕过黑名单看
  /// 这个标签，现在它不再被屏蔽，绕过就没有意义了，重选一次把标记清干净
  /// （结果集完全一样，只是把那一位状态归零）。
  ///
  /// [tagId] 传空表示「整份名单都变了」（清空），不需要做那项残留清理。
  Future<void> reloadAfterUnblock({int? tagId}) async {
    final tag = state.tag;
    if (tagId != null &&
        state.bypassBlocklist &&
        state.source == OnlineSource.tag &&
        tag != null &&
        tag.id == tagId) {
      await selectTag(tag);
      return;
    }
    await _reloadFromFirstPage();
  }

  /// 回到第 1 页重拉。**刻意不留在原页**：结果集变小之后原页可能已经没有内容
  /// （`totalPages` 一起变小），停在原页会得到「共 2 页」而列表空白的自相矛盾状态。
  Future<void> _reloadFromFirstPage() async {
    state = state.copyWith(
      works: const [],
      page: 1,
      totalCount: 0,
      loading: true,
      clearError: true,
    );
    await _fetch(1);
  }

  /// 跳到指定页（越界自动夹到有效范围）
  Future<void> goToPage(int page) async {
    if (state.loading || state.totalPages <= 0) return;
    final target = page.clamp(1, state.totalPages);
    if (target == state.page && state.works.isNotEmpty) return;
    state = state.copyWith(loading: true, clearError: true);
    await _fetch(target);
  }

  /// 切换每页条数：回到第 1 页（保持行号语义简单，不做页码换算）。
  /// 1.97.0 起同步落盘，冷启动由构造器恢复。
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
    unawaited(
      _ref.read(settingsProvider.notifier).setOnlinePageSize(size.toDouble()),
    );
    await _fetch(1);
  }

  Future<void> _fetch(int page) async {
    final tag = state.tag;
    if (state.source == OnlineSource.tag && tag == null) {
      // 「按标签筛选」而没有标签（正常流程到不了，但状态是可构造的）。
      // 早退而不是往下走：`fetchWorksByTag` 需要 label 名，而打到
      // `/api/tags/0/works` 会拿回一个语义不明的 400/空页。
      state = state.copyWith(
        works: const [],
        totalCount: 0,
        page: 1,
        loading: false,
        clearError: true,
      );
      return;
    }

    final client = _ref.read(onlineClientProvider);
    final size = state.pageSize;
    final sort = state.sort;

    // 黑名单（1.95.0）在**每次请求前**现取：用户刚在设置里加了标签，
    // 回来点一下刷新就该生效，不该等重建 notifier。
    //
    // `bypassBlocklist` 只把那一个标签从排除项里摘出来，其余照旧
    // （见 `OnlineBrowseState.bypassBlocklist` 的注释）。
    final blocked = _ref.read(settingsProvider).blockedTags;
    final exclude = exclusionKeyword(
      state.bypassBlocklist && tag != null
          ? blocked.where((t) => t.id != tag.id)
          : blocked,
    );

    // 声优 / 社团筛选（1.97.0）：`/api/works` 会静默丢弃关键词（黑名单 1.95.0
    // 同款坑），所以 creator 激活时一律改走搜索接口 —— 与「黑名单激活」的
    // 端点映射完全同构，两者可以叠加（关键词里各占一段）。
    final creatorTerm = state.creator?.term ?? '';

    try {
      final result = await switch (state.source) {
        OnlineSource.browse => creatorTerm.isEmpty
            ? client.fetchWorks(
                page: page,
                pageSize: size,
                sort: sort,
                subtitleOnly: state.subtitleOnly,
                excludeKeyword: exclude,
              )
            : client.searchWorks(
                creatorTerm,
                page: page,
                pageSize: size,
                sort: sort,
                excludeKeyword: exclude,
              ),
        OnlineSource.search => client.searchWorks(
            creatorTerm.isEmpty
                ? state.keyword
                : '$creatorTerm ${state.keyword}',
            page: page,
            pageSize: size,
            sort: sort,
            excludeKeyword: exclude,
          ),
        OnlineSource.tag => creatorTerm.isEmpty
            ? client.fetchWorksByTag(
                tag!,
                page: page,
                pageSize: size,
                sort: sort,
                excludeKeyword: exclude,
              )
            // 结构化标签端点同样吃不下 creator，换成实测等价的 `$tag:` 关键词
            : client.searchWorks(
                '${tagIncludeTerm(tag!.name.trim())} $creatorTerm',
                page: page,
                pageSize: size,
                sort: sort,
                excludeKeyword: exclude,
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

/// 当前黑名单的**标签 id 集合**。
///
/// 卡片 / 详情页里每个标签胶囊都要问一句「我被屏蔽了吗」，而 `isTagBlocked`
/// 需要的是集合而不是列表 —— 在 provider 这一层算一次，界面侧就不必各自
/// 现建 Set（一页 20 张卡片、每张十几个标签，那是几百次建集合）。
///
/// 用 `select` 而不是整份 settings：改主题、改音量都不该让整页标签重绘。
final blockedTagIdsProvider = Provider<Set<int>>(
  (ref) => blockedIdSet(
    ref.watch(settingsProvider.select((s) => s.blockedTags)),
  ),
);

// 标签表（`/api/tags/`，422 个约 72KB）**1.94.0 起不再需要**。
//
// 1.93 及以前是在详情页点标签后、拿标签名来这里反查 id（`_openTagByName`）。
// 1.94.0 发现列表/详情响应的 `tags` 本来就带 `id`，于是整条反查链路连同这个
// provider 一起删掉 —— 留着它会是一份随时可能被误 watch（白拉 72KB）的死接线。
// `KikoeruClient.fetchTags()` 保留：那是「一个服务端端点一个方法」的 API 表面，
// 将来若做标签选择器还会用到。

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
      // 这是「在线作品 → 本地播放用 Album」的投影，只取标签名（Album.tags 是字符串表）
      tags: work.tags.map((t) => t.name).toList(),
      group: '在线',
      genre: '在线',
      duration: tracks.length,
      date: DateTime.now(),
      tracks: tracks,
      localCover: client.coverMainUrl(work.id),
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
