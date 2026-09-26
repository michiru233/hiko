import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../widgets/detail_kit.dart';
import '../widgets/online_account_dialogs.dart';
import '../widgets/online_cover.dart';
import '../widgets/online_detail_panel.dart';
import '../widgets/online_tag_menu.dart';
import '../widgets/online_work_grid.dart';
import '../widgets/toast.dart';

/// 顶部两个预设入口：chip 上的短名 + 它指向的排序项。
///
/// 1.92.0 起 chip **只是排序预设**（裁决 Q4=A），不再是「数据来源」——
/// 两者都走 `/api/works`，区别仅在于把排序切到销量还是发售日期。
const List<(OnlineSort, String)> _onlinePresets = [
  (OnlineSort.popularPreset, '热门'),
  (OnlineSort.latestPreset, '最新'),
];

/// 在线音声视图（Kikoeru / asmr.one）。
///
/// 数据完全来自远程服务，不进本地库——在线专辑只在播放时构造为内存态 `Album`。
///
/// 桌面端：左侧列表 + 右侧详情面板；移动端：详情走全屏页。
///
/// 1.92.0：筛选条改版（裁决 Q4=A / Q6=① / Q7=A / Q8=A / Q11=A）——
/// 热门/最新 退化为排序预设，「排序」改成一列扁平下拉（方向写进条目名，对齐
/// asmr.one），「只看带字幕」独立成 chip 且只对全站浏览可用。
///
/// 1.93.0：右上角加账号入口（裁决 Q2=C），列表封面改原图、卡片加收藏角标（Q5=A）。
class OnlineScreen extends ConsumerStatefulWidget {
  const OnlineScreen({
    super.key,
    required this.isMobile,
    this.onOpenFavorites,
  });

  final bool isMobile;

  /// 切到「在线收藏」视图。账号菜单里的入口用 —— 视图归属在 home_screen，
  /// 这里只上报意图
  final VoidCallback? onOpenFavorites;

  @override
  ConsumerState<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends ConsumerState<OnlineScreen> {
  final _searchController = TextEditingController();
  int? _detailWorkId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 首次进入时自动拉一次热门榜；已有数据则不打扰（切走再切回不重新加载）
  void _ensureLoaded() {
    if (!mounted) return;
    final state = ref.read(onlineBrowseProvider);
    if (state.works.isEmpty && !state.loading) {
      unawaited(
        ref
            .read(onlineBrowseProvider.notifier)
            .applyPreset(OnlineSort.popularPreset),
      );
    }
  }

  Future<void> _submitSearch(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) {
      await ref
          .read(onlineBrowseProvider.notifier)
          .applyPreset(OnlineSort.popularPreset);
      return;
    }
    await ref.read(onlineBrowseProvider.notifier).search(keyword);
  }

  /// 点标签 → 按该标签筛选（1.94.0，裁决 Q2=甲：走结构化标签端点）。
  ///
  /// 再点**同一个**标签 = 取消（裁决 Q3=A），按用户裁决一律回**最新榜**。
  ///
  /// 顺带把两处「另一件事的残留」清掉：
  /// - **搜索框文本**：状态里的 `keyword` 早就被 `selectTag` 清空了，输入框却还留着
  ///   上次输入的词，会出现「框里写着 abc、结果其实是标签的」这种自相矛盾。
  ///   这条不只是为新功能 —— 1.94.0 之前在详情页点标签就有这个毛病。
  /// - **右侧详情面板**：面板上那个作品多半已经不在新结果里了，留着等于指鹿为马。
  ///
  /// 不需要额外把列表滚回顶部：`selectTag` / `applyPreset` 都会清空 `works`，
  /// 网格那一帧就被 loading 占位换掉了，`GridView` 重建后天然从头开始。
  ///
  /// 1.95.0：标签已在黑名单里时要**先确认**（裁决 Q5）。确认这一步放在函数最前面 ——
  /// 用户若取消，搜索框与详情面板都不该已经被动过。
  Future<void> _applyTag(OnlineTag tag) async {
    final browse = ref.read(onlineBrowseProvider);
    final cancelling =
        browse.source == OnlineSource.tag && browse.tag?.id == tag.id;

    var bypass = false;
    if (!cancelling) {
      final decision = await resolveBlockedTagFilter(context, ref, tag);
      if (decision == null || !mounted) return;
      bypass = decision;
    }

    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      if (mounted) setState(() {});
    }
    if (_detailWorkId != null && mounted) {
      setState(() => _detailWorkId = null);
    }

    final notifier = ref.read(onlineBrowseProvider.notifier);
    if (cancelling) {
      await notifier.applyPreset(OnlineSort.latestPreset);
      return;
    }
    await notifier.selectTag(tag, bypassBlocklist: bypass);
  }

  void _openDetail(int workId) {
    if (widget.isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OnlineDetailScreen(
            workId: workId,
            // 移动端的详情是整页盖在列表上，点完标签要把这页收起来才看得到结果
            onSelectTag: (tag) {
              unawaited(_applyTag(tag));
              Navigator.of(context).maybePop();
            },
          ),
        ),
      );
      return;
    }
    setState(() => _detailWorkId = workId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onlineBrowseProvider);
    final theme = Theme.of(context);
    final showPanel = !widget.isMobile && _detailWorkId != null;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(state, theme),
              Expanded(child: _buildResults(state, theme)),
            ],
          ),
        ),
        if (showPanel) ...[
          VerticalDivider(
            width: 1,
            color: theme.dividerColor.withValues(alpha: 0.4),
          ),
          SizedBox(
            // 与本地详情抽屉同宽（390），两处详情页观感一致
            width: 390,
            child: OnlineDetailPanel(
              workId: _detailWorkId!,
              onClose: () => setState(() => _detailWorkId = null),
              onSelectTag: _applyTag,
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- 顶栏

  Widget _buildHeader(OnlineBrowseState state, ThemeData theme) {
    final pad = widget.isMobile ? 16.0 : 48.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 2, pad, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (preset, label) in _onlinePresets)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: state.isPresetActive(preset),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => unawaited(
                      ref
                          .read(onlineBrowseProvider.notifier)
                          .applyPreset(preset),
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Expanded(child: _buildSearchField(theme)),
              const SizedBox(width: 8),
              // 账号入口（裁决 Q2=C：在线页右上角 + 设置里的二级页）
              _OnlineAccountEntry(
                compact: widget.isMobile,
                onOpenFavorites: widget.onOpenFavorites,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildFilterLine(state, theme),
        ],
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 12),
        onSubmitted: (value) => unawaited(_submitSearch(value)),
        onChanged: (_) => setState(() {}), // 刷新清除按钮的显隐
        decoration: InputDecoration(
          isDense: true,
          hintText: '搜索在线作品（日文原关键词命中率最高）',
          hintStyle: TextStyle(fontSize: 12, color: theme.hintColor),
          prefixIcon: const Icon(Icons.search, size: 16),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 30),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  tooltip: '清除',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    unawaited(ref
                        .read(onlineBrowseProvider.notifier)
                        .applyPreset(OnlineSort.popularPreset));
                  },
                ),
          suffixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 30),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  /// 第二行：字幕筛选（仅全站浏览可用）+ 排序下拉 + 状态行。
  ///
  /// 状态行右对齐并留出固定间距 —— 旧版紧贴在左边控件后面，读起来像它的后缀。
  Widget _buildFilterLine(OnlineBrowseState state, ThemeData theme) {
    // 数量从 settings 取，与黑名单管理对话框里列出的条数同源 ——
    // 用 id 集合的 size 会让「id 为 0 的坏数据」在两处显示成不同的数字
    final blockedCount =
        ref.watch(settingsProvider.select((s) => s.blockedTags.length));
    return Row(
      children: [
        if (state.canFilterSubtitle) ...[
          FilterChip(
            label: const Text('只看带字幕', style: TextStyle(fontSize: 11)),
            selected: state.subtitleOnly,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => unawaited(
              ref.read(onlineBrowseProvider.notifier).toggleSubtitleOnly(),
            ),
          ),
          const SizedBox(width: 8),
        ],
        _SortMenu(
          current: state.sort,
          onSelected: (sort) =>
              ref.read(onlineBrowseProvider.notifier).setSort(sort),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // 黑名单的可点标记（1.95.0 裁决 Q1=甲）：黑名单是**看不见的筛选**，
                // 不给出口的话用户只会觉得「搜不到东西」，而这是他自己设的
                if (blockedCount > 0) ...[
                  _BlockedTagsMarker(
                    count: blockedCount,
                    onTap: () => unawaited(showOnlineBlacklistDialog(context)),
                  ),
                  const SizedBox(width: 8),
                ],
                // 标签筛选的可关闭标记（1.94.0 裁决 Q7=甲）。
                // 卡面标签是散落入口，一屏可能十几个不同标签，点下去之后必须有个
                // 看得见的出口，否则用户不知道自己被筛在哪、怎么回去。
                if (state.source == OnlineSource.tag && state.tag != null) ...[
                  _TagFilterMarker(
                    tag: state.tag!.name,
                    onClear: () => unawaited(_applyTag(state.tag!)),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    _statusLine(state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: theme.hintColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 状态行文案 = 数据来源 + 当前排序（裁决 Q11=A）。
  /// 命中预设时用榜单名（热门榜 / 最新上架），否则老实说出「全部作品 · 评价倒序」。
  ///
  /// 标签筛选下**不再重复标签名** —— 名字由旁边那个可关闭标记承担，这里只报数量。
  String _statusLine(OnlineBrowseState state) {
    // 换页期间旧结果还留在屏上（顶上压着进度条），不算「正在连接」
    if (state.loading && state.works.isEmpty) return '正在连接在线服务器…';
    if (state.error != null && state.works.isEmpty) return '';
    final head = switch (state.source) {
      OnlineSource.browse => switch (state.sort) {
          OnlineSort.dlCountDesc => '热门榜',
          OnlineSort.releaseDesc => '最新上架',
          final other => '全部作品 · ${other.label}',
        },
      OnlineSource.search => '搜索「${state.keyword}」',
      OnlineSource.tag => '',
    };
    final total = state.totalCount > 0
        ? '共 ${formatOnlineCount(state.totalCount)} 件'
        : '';
    // 「仍要查看」是一次性例外，明写出来 —— 否则用户看不出这一页为什么
    // 还会冒出被屏蔽标签的作品
    return [
      if (head.isNotEmpty) head,
      if (total.isNotEmpty) total,
      if (state.bypassBlocklist) '未套黑名单',
    ].join(' · ');
  }

  // ---------------------------------------------------------------- 结果

  Widget _buildResults(OnlineBrowseState state, ThemeData theme) {
    if (state.loading && state.works.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (state.error != null && state.works.isEmpty) {
      return _OnlineError(
        message: state.error!,
        onRetry: () => unawaited(
          ref.read(onlineBrowseProvider.notifier).refresh(),
        ),
      );
    }
    if (state.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 30, color: theme.hintColor),
            const SizedBox(height: 10),
            Text(
              state.source == OnlineSource.search ? '没有找到匹配的作品' : '没有拿到数据',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        // 翻页请求期间旧页仍在屏上，用一条细进度条说明「正在换页」
        SizedBox(
          height: 2,
          child: state.loading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Expanded(child: _buildGrid(state)),
        _buildPager(state),
      ],
    );
  }

  Widget _buildGrid(OnlineBrowseState state) {
    final showTags = ref.watch(settingsProvider).showOnlineTags;
    return OnlineWorkGrid(
      works: state.works,
      isMobile: widget.isMobile,
      selectedId: _detailWorkId,
      onTap: (work) => _openDetail(work.id),
      showTags: showTags,
      onTagTap: (tag) => unawaited(_applyTag(tag)),
    );
  }

  // ---------------------------------------------------------------- 分页条

  /// 经典分页条（裁决 Q6=A）：每页条数 + 首页/末页 + 上一页/下一页 +
  /// 当前页 ±2 的页码 + 跳页输入。1.93.0 起与在线收藏页共用同一个组件。
  Widget _buildPager(OnlineBrowseState state) {
    final notifier = ref.read(onlineBrowseProvider.notifier);
    return OnlinePager(
      page: state.page,
      pageSize: state.pageSize,
      totalCount: state.totalCount,
      isMobile: widget.isMobile,
      onPage: (page) => unawaited(notifier.goToPage(page)),
      onPageSize: (size) => unawaited(notifier.setPageSize(size)),
    );
  }
}

/// 排序下拉（裁决 Q6=①）。
///
/// 形态对齐 asmr.one 的「排序」菜单：**一条扁平列表，方向写进条目名**
/// （「销量倒序」而不是「销量」+独立箭头），因此没有「再点一次反转」这种隐藏状态。
///
/// 限高是为了安卓：竖屏高度有限，菜单不该顶到天花板。`PopupMenu` 的菜单体本来就是
/// `SingleChildScrollView`，所以给出 `maxHeight` 即自动获得滚动，不必自己实现。
/// 当前 5 项在桌面与多数手机上都不会触发滚动，护栏留给以后加条目时用。
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.current, required this.onSelected});

  final OnlineSort current;
  final Future<void> Function(OnlineSort sort) onSelected;

  /// min(320, 屏高 × 0.45)：小屏按比例缩，大屏封顶
  static double _menuMaxHeight(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).height;
    final scaled = screen * 0.45;
    return scaled < 320 ? scaled : 320;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<OnlineSort>(
      tooltip: '排序方式',
      constraints: BoxConstraints(
        minWidth: 200,
        maxWidth: 280,
        maxHeight: _menuMaxHeight(context),
      ),
      onSelected: (sort) => unawaited(onSelected(sort)),
      itemBuilder: (_) => [
        for (final sort in OnlineSort.values)
          PopupMenuItem<OnlineSort>(
            value: sort,
            height: 38,
            child: SizedBox(
              // 固定宽度让条目里的 Expanded 有确定边界，菜单宽度也就可预期
              width: 168,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      sort.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  if (sort == current)
                    Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                ],
              ),
            ),
          ),
      ],
      child: Chip(
        label: Text('排序：${current.label}', style: const TextStyle(fontSize: 11)),
        avatar: const Icon(Icons.swap_vert_rounded, size: 13),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 在线页右上角的账号入口（1.93.0，裁决 Q2=C）。
///
/// 三种形态跟着登录态走：**恢复中**显示一个小转圈（不是「登录」——
/// 冷启动那一下会误报未登录）、**未登录**是一个「登录」按钮、**已登录**是
/// 一个带名字的胶囊，点开是收藏/刷新/登出。
///
/// 移动端退化成纯图标：竖屏一行要同时塞下两个预设 chip、搜索框和这个入口，
/// 带文字会被挤成省略号。
class _OnlineAccountEntry extends ConsumerWidget {
  const _OnlineAccountEntry({required this.compact, this.onOpenFavorites});

  final bool compact;
  final VoidCallback? onOpenFavorites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final account = ref.watch(onlineAccountProvider);

    if (account.restoring) {
      return SizedBox(
        width: compact ? 34 : 56,
        height: 32,
        child: const Center(
          child: SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (!account.loggedIn) {
      if (compact) {
        return IconButton(
          tooltip: '登录 asmr.one',
          onPressed: () => unawaited(showOnlineLoginDialog(context)),
          icon: const Icon(Icons.person_outline_rounded, size: 18),
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
          padding: EdgeInsets.zero,
        );
      }
      return TextButton.icon(
        onPressed: () => unawaited(showOnlineLoginDialog(context)),
        icon: const Icon(Icons.person_outline_rounded, size: 15),
        label: const Text('登录', style: TextStyle(fontSize: 11)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return PopupMenuButton<_AccountAction>(
      tooltip: compact ? account.displayName : '在线账号',
      onSelected: (action) => unawaited(_handle(ref, context, action)),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          height: 32,
          child: Text(
            '已登录：${account.displayName}',
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
        ),
        const PopupMenuDivider(height: 1),
        const PopupMenuItem(
          value: _AccountAction.favorites,
          height: 36,
          child: Text('在线收藏', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem(
          value: _AccountAction.refresh,
          height: 36,
          child: Text('刷新收藏', style: TextStyle(fontSize: 12)),
        ),
        const PopupMenuItem(
          value: _AccountAction.logout,
          height: 36,
          child: Text('退出登录', style: TextStyle(fontSize: 12)),
        ),
      ],
      child: compact
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.account_circle_rounded, size: 22),
            )
          : Chip(
              avatar: const Icon(Icons.account_circle_rounded, size: 14),
              label: Text(
                account.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              visualDensity: VisualDensity.compact,
            ),
    );
  }

  Future<void> _handle(
    WidgetRef ref,
    BuildContext context,
    _AccountAction action,
  ) async {
    switch (action) {
      case _AccountAction.favorites:
        onOpenFavorites?.call();
      case _AccountAction.refresh:
        await ref.read(onlineFavoritesProvider.notifier).refresh();
        if (!context.mounted) return;
        final state = ref.read(onlineFavoritesProvider);
        showHikoToast(
          context,
          state.error == null
              ? '已刷新 ${state.index.playlists.length} 个歌单'
              : '刷新失败：${state.error}',
        );
      case _AccountAction.logout:
        await ref.read(onlineAccountProvider.notifier).logout();
        if (context.mounted) showHikoToast(context, '已退出登录');
    }
  }
}

enum _AccountAction { favorites, refresh, logout }

/// 在线作品卡片：封面（原图）+ 标题 + 社团/下载量
///
/// 1.92.0 之前列表用 `type=240x240` 缩略图（实测 240×180），卡片在 Retina 上
/// 需要 400–520 物理像素，`BoxFit.cover` 裁方形后只剩 180×180 → 放大 2.4–2.9 倍，
/// 于是「主界面封面模糊、详情页正常」。服务端没有中间档，1.93.0 起统一走原图
/// （裁决 Q4=A：不加清晰度开关）。
class OnlineWorkCard extends ConsumerWidget {
  const OnlineWorkCard({
    super.key,
    required this.work,
    required this.onTap,
    this.selected = false,
    this.onContextMenu,
    this.showTags = false,
    this.onTagTap,
  });

  final OnlineWork work;
  final VoidCallback onTap;
  final bool selected;

  /// 右键（桌面）/ 长按（触屏）菜单：在线收藏页用来提供「加入其它歌单 / 移出本歌单」
  final void Function(Offset globalPosition)? onContextMenu;

  /// 是否显示卡面标签行（1.94.0）
  final bool showTags;

  /// 点标签 → 按该标签筛选；为 null 时标签只展示
  final ValueChanged<OnlineTag>? onTagTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coverUrl = ref.watch(onlineClientProvider).coverMainUrl(work.id);
    // 收藏角标：作品在任意歌单里就点亮。未登录/索引未就绪时索引为空，自然不亮
    final favoritePlaylists =
        ref.watch(onlineFavoritesProvider).index.playlistsOf(work.id);
    // 被屏蔽的标签在卡面上弱化显示（1.95.0 裁决 Q4=乙、Q5 不隐藏）：
    // 作品本身还在结果里（服务端已经滤掉该标签的作品了，能出现在这儿说明它
    // 是靠别的标签命中的），所以只把「这一个标签」标出来，不是把卡片灰掉。
    final blockedTagIds = ref.watch(blockedTagIdsProvider);

    final subtitle = [
      if (work.circleName.isNotEmpty) work.circleName,
      if (work.dlCount > 0) '↓${formatOnlineCount(work.dlCount)}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      onSecondaryTapDown: onContextMenu == null
          ? null
          : (d) => onContextMenu!(d.globalPosition),
      onLongPress: onContextMenu == null
          ? null
          : () {
              // 触屏没有右键：长按落在卡片中央，菜单跟随该点弹出
              final box = context.findRenderObject() as RenderBox?;
              final origin = box == null
                  ? Offset.zero
                  : box.localToGlobal(box.size.center(Offset.zero));
              onContextMenu!(origin);
            },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OnlineCover(url: coverUrl),
                    if (work.hasSubtitle)
                      const Positioned(left: 6, bottom: 6, child: _SubtitleBadge()),
                    if (favoritePlaylists.isNotEmpty)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: _FavoriteBadge(count: favoritePlaylists.length),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              work.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, height: 1.3),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
            // 标签行：固定高度（网格靠它算卡高），所以即使没有标签也要占位，
            // 否则同一屏里没标签的卡片会把空高还给封面、显得比别的大。
            // 用 bottomLeft 对齐，把省下的高度全留在与副标题之间当间距。
            if (showTags)
              SizedBox(
                height: kOnlineCardTagRow,
                child: work.tags.isEmpty
                    ? null
                    : Align(
                        alignment: Alignment.bottomLeft,
                        child: _CardTagRow(
                          tags: work.tags,
                          blockedIds: blockedTagIds,
                          onTagTap: onTagTap,
                          onTagMenu: (tag, position) => unawaited(
                            showOnlineTagMenu(
                              context: context,
                              ref: ref,
                              tag: tag,
                              position: position,
                              onFilter: onTagTap == null
                                  ? null
                                  : () => onTagTap!(tag),
                            ),
                          ),
                          // `+N` 与卡片同义：打开详情看全部标签
                          onMoreTap: onTap,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 卡面标签行：**单行**，能放几个放几个，放不下的收进 `+N`。
///
/// 为什么不做换行：在线用的是 `SliverGrid`（固定高度），多行会让同一屏的卡片
/// 互相打架；本地卡面能换行是因为本地是 masonry 可变高布局。所以这里的策略是
/// 「按像素实测宽度挑选前缀 + `+N` 永远保留一个位置」。
///
/// 宽度是用 [TextPainter] 真量出来的，不是按字数估：标签名长短差异极大
/// （「ASMR」4 个字符 vs「双声道立体声/人头麦」10 个字符），估算必然翻车。
/// 量与画都从 [HikoTagChip.textStyle] / [HikoTagChip.horizontalPadding] 取，保证一致。
class _CardTagRow extends StatelessWidget {
  const _CardTagRow({
    required this.tags,
    required this.onMoreTap,
    this.blockedIds = const {},
    this.onTagTap,
    this.onTagMenu,
  });

  final List<OnlineTag> tags;
  final VoidCallback onMoreTap;
  final ValueChanged<OnlineTag>? onTagTap;

  /// 已被加入黑名单的标签 id（1.95.0）。命中的胶囊灰掉 + 删除线
  final Set<int> blockedIds;

  /// 右键（桌面）/ 长按（触屏）标签 → 弹出标签菜单。回调里给的是**全局**坐标
  final void Function(OnlineTag tag, Offset globalPosition)? onTagMenu;

  static const _gap = 5.0;

  @override
  Widget build(BuildContext context) {
    // 文字缩放必须带进宽度预算（1.95.0 修）：
    // 全局 `fontScale` 是挂在根层的 `TextScaler`，`HikoTagChip` 画出来的是
    // 9pt × scaler，而这里若按 9pt 量宽度，用户把字号调到大/超大时就是
    // 「量少画宽」—— 标签行当场溢出卡片。量与画必须用同一个 scaler。
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final widths = [for (final t in tags) _chipWidth(t.name, scaler)];
        double rowWidth(int count) {
          if (count <= 0) return 0;
          var w = 0.0;
          for (var i = 0; i < count; i++) {
            w += widths[i];
          }
          return w + _gap * (count - 1);
        }

        // 先按**最长可能**的 `+N` 宽度预留（总标签数）。实际渲染时用的是
        // 「被藏起来的个数」，位数只会更少，所以预留下来的宽度一定够。
        final moreWidth = _chipWidth('+${tags.length}', scaler);

        var visible = tags.length;
        var showMore = false;
        if (rowWidth(tags.length) > maxWidth) {
          // 放不下全部：从「尽量多」往下退，退到「能塞下 k 个 + +N」为止
          showMore = true;
          visible = 0;
          for (var k = tags.length - 1; k >= 1; k--) {
            if (rowWidth(k) + _gap + moreWidth <= maxWidth) {
              visible = k;
              break;
            }
          }
        }

        return Row(
          children: [
            for (final tag in tags.take(visible))
              Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: HikoTagChip(
                  tag: tag.name,
                  blocked: blockedIds.contains(tag.id),
                  // id <= 0 表示服务端只给了名字，筛不了也屏蔽不了，只能看
                  onTap: onTagTap == null || tag.id <= 0
                      ? null
                      : () => onTagTap!(tag),
                  onContextMenu: onTagMenu == null
                      ? null
                      : (position) => onTagMenu!(tag, position),
                ),
              ),
            if (showMore)
              HikoTagChip(
                // 与本地卡面同一套约定：`+N` 是**被藏起来的**个数，不是总数
                tag: '+${tags.length - visible}',
                onTap: onMoreTap,
                muted: true,
              ),
          ],
        );
      },
    );
  }

  /// 胶囊宽度 = 文字宽 + 左右内边距 + 1px 余量（四舍五入误差不该让它挤掉下一枚）
  static double _chipWidth(String text, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: HikoTagChip.textStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width + HikoTagChip.horizontalPadding * 2 + 1;
  }
}

/// 标签筛选的可关闭标记（1.94.0 裁决 Q7=甲）。
///
/// 形态照搬本地 1.77 那套「社团 / 声优」标记：淡色胶囊 + 尾巴上的 ✕，
/// 颜色用标签自己的青色，和卡面标签保持同一套配色。
class _TagFilterMarker extends StatelessWidget {
  const _TagFilterMarker({required this.tag, required this.onClear});

  final String tag;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Flexible(
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 3, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: hikoTagBgColor.withValues(alpha: isDark ? 0.2 : 0.8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标签名可能很长（「双声道立体声/人头麦」），限宽让它自己省略，
            // 不能让它把右边的数量挤没
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                '标签：$tag',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: hikoTagFgColor),
              ),
            ),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(8),
              child: const Tooltip(
                message: '退出标签筛选',
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 13, color: hikoTagFgColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 黑名单的可点标记（1.95.0 裁决 Q1=甲）。
///
/// 为什么必须有它：黑名单和标签筛选不一样 —— 标签筛选是用户**刚做过**的动作，
/// 而黑名单是**很久以前**在设置里攒下来的状态。没有可见标记的话，用户看到
/// 「明明搜得到的东西不见了」时只会以为是服务器的问题，因为屏幕上没有任何线索
/// 指向「是你自己屏蔽的」。
///
/// 形态刻意比 [_TagFilterMarker] 低调（灰系、无彩色），因为它是**背景状态**而
/// 不是「你正在看什么」。点开进管理页，是唯一的出口。
class _BlockedTagsMarker extends StatelessWidget {
  const _BlockedTagsMarker({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.hintColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Tooltip(
        message: '管理标签黑名单',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block_rounded, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                '已屏蔽 $count 个标签',
                style: TextStyle(fontSize: 11, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleBadge extends StatelessWidget {
  const _SubtitleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        '字幕',
        style: TextStyle(fontSize: 9, color: Colors.white),
      ),
    );
  }
}

/// 收藏角标（裁决 Q5=A）：作品在任意歌单里就点亮，在多个歌单时带数量。
///
/// 用书签而不是心形 —— 歌单里除了「我喜欢的」，还有「听完」「未听」这类
/// 状态分类，心形会把语义带偏。
class _FavoriteBadge extends StatelessWidget {
  const _FavoriteBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_rounded, size: 10, color: Colors.white),
          if (count > 1) ...[
            const SizedBox(width: 2),
            Text(
              '$count',
              style: const TextStyle(fontSize: 9, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnlineError extends StatelessWidget {
  const _OnlineError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 32, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
