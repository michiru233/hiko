import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/kikoeru_client.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../widgets/online_cover.dart';
import '../widgets/online_detail_panel.dart';

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
class OnlineScreen extends ConsumerStatefulWidget {
  const OnlineScreen({super.key, required this.isMobile});

  final bool isMobile;

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

  /// 详情页点标签 → 按标签继续浏览。
  /// 详情接口只给标签名，需要拿标签表反查 id。
  Future<void> _openTagByName(String name) async {
    try {
      final tags = await ref.read(onlineTagsProvider.future);
      final match = tags.where((t) => t.name == name);
      if (match.isEmpty) {
        _toast('没找到「$name」对应的筛选标签');
        return;
      }
      await ref.read(onlineBrowseProvider.notifier).selectTag(match.first);
      if (!mounted) return;
      if (widget.isMobile) {
        Navigator.of(context).maybePop(); // 返回列表看筛选结果
      } else {
        setState(() => _detailWorkId = null);
      }
    } catch (e) {
      _toast('标签加载失败：$e');
    }
  }

  void _openDetail(int workId) {
    if (widget.isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OnlineDetailScreen(
            workId: workId,
            onSelectTagName: _openTagByName,
          ),
        ),
      );
      return;
    }
    setState(() => _detailWorkId = workId);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
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
              onSelectTagName: _openTagByName,
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
            child: Text(
              _statusLine(state),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ),
        ),
      ],
    );
  }

  /// 状态行文案 = 数据来源 + 当前排序（裁决 Q11=A）。
  /// 命中预设时用榜单名（热门榜 / 最新上架），否则老实说出「全部作品 · 评价倒序」。
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
      OnlineSource.tag => '标签「${state.tag?.name ?? ''}」',
    };
    final total = state.totalCount > 0
        ? '共 ${formatOnlineCount(state.totalCount)} 件'
        : '';
    return total.isEmpty ? head : '$head · $total';
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
        _buildPager(state, theme),
      ],
    );
  }

  Widget _buildGrid(OnlineBrowseState state) {
    final pad = widget.isMobile ? 16.0 : 48.0;
    const spacing = 14.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - pad * 2;
        final columns = widget.isMobile
            ? 2
            : ((available + spacing) / (200 + spacing)).floor().clamp(3, 8);
        final cardWidth = (available - spacing * (columns - 1)) / columns;
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            // 封面正方形 + 两行标题 + 一行副标题，用固定高度避免不同标题把网格撑歪
            mainAxisExtent: cardWidth + 62,
          ),
          itemCount: state.works.length,
          itemBuilder: (context, index) {
            final work = state.works[index];
            return OnlineWorkCard(
              work: work,
              selected: _detailWorkId == work.id,
              onTap: () => _openDetail(work.id),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------- 分页条

  /// 经典分页条（裁决 Q6=A）：每页条数 + 首页/末页 + 上一页/下一页 +
  /// 当前页 ±2 的页码 + 跳页输入。
  Widget _buildPager(OnlineBrowseState state, ThemeData theme) {
    final total = state.totalPages;
    final pad = widget.isMobile ? 16.0 : 48.0;
    final notifier = ref.read(onlineBrowseProvider.notifier);

    return Container(
      padding: EdgeInsets.fromLTRB(pad, 6, pad, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          _PageSizeButton(state: state, onSelected: notifier.setPageSize),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PagerIcon(
                    icon: Icons.first_page_rounded,
                    tooltip: '首页',
                    onPressed: state.hasPrev ? () => notifier.goToPage(1) : null,
                  ),
                  _PagerIcon(
                    icon: Icons.chevron_left_rounded,
                    tooltip: '上一页',
                    onPressed: state.hasPrev
                        ? () => notifier.goToPage(state.page - 1)
                        : null,
                  ),
                  for (final item in buildPageItems(state.page, total))
                    if (item == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '…',
                          style: TextStyle(fontSize: 11, color: theme.hintColor),
                        ),
                      )
                    else
                      _PageNumberButton(
                        page: item,
                        current: item == state.page,
                        onPressed: () => notifier.goToPage(item),
                      ),
                  _PagerIcon(
                    icon: Icons.chevron_right_rounded,
                    tooltip: '下一页',
                    onPressed: state.hasNext
                        ? () => notifier.goToPage(state.page + 1)
                        : null,
                  ),
                  _PagerIcon(
                    icon: Icons.last_page_rounded,
                    tooltip: '末页',
                    onPressed:
                        state.hasNext ? () => notifier.goToPage(total) : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _PageJumpField(totalPages: total, onSubmit: notifier.goToPage),
        ],
      ),
    );
  }
}

/// 每页条数选择（20 / 60 / 100；实测服务端支持到 500）
class _PageSizeButton extends StatelessWidget {
  const _PageSizeButton({required this.state, required this.onSelected});

  final OnlineBrowseState state;
  final Future<void> Function(int size) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: '每页条数',
      onSelected: (size) => unawaited(onSelected(size)),
      itemBuilder: (_) => [
        for (final size in OnlineBrowseNotifier.pageSizeOptions)
          PopupMenuItem(
            value: size,
            child: Text('每页 $size 条', style: const TextStyle(fontSize: 12)),
          ),
      ],
      child: Chip(
        label: Text('每页 ${state.pageSize} 条', style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _PagerIcon extends StatelessWidget {
  const _PagerIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
      padding: EdgeInsets.zero,
    );
  }
}

class _PageNumberButton extends StatelessWidget {
  const _PageNumberButton({
    required this.page,
    required this.current,
    required this.onPressed,
  });

  final int page;
  final bool current;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: SizedBox(
        height: 28,
        child: TextButton(
          onPressed: current ? null : onPressed,
          style: TextButton.styleFrom(
            minimumSize: const Size(32, 28),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            backgroundColor: current
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            '$page',
            style: TextStyle(
              fontSize: 11,
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: current ? theme.colorScheme.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// 跳页输入：回车生效，越界由控制器夹到有效范围
class _PageJumpField extends StatefulWidget {
  const _PageJumpField({required this.totalPages, required this.onSubmit});

  final int totalPages;
  final Future<void> Function(int page) onSubmit;

  @override
  State<_PageJumpField> createState() => _PageJumpFieldState();
}

class _PageJumpFieldState extends State<_PageJumpField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '共 ${widget.totalPages} 页',
          style: TextStyle(fontSize: 11, color: theme.hintColor),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          height: 28,
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              isDense: true,
              hintText: '跳页',
              hintStyle: TextStyle(fontSize: 11, color: theme.hintColor),
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (value) {
              final page = int.tryParse(value.trim());
              if (page == null) return;
              widget.onSubmit(page);
              _controller.clear();
            },
          ),
        ),
      ],
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

/// 在线作品卡片：封面（240x240 缩略图）+ 标题 + 社团/下载量
class OnlineWorkCard extends ConsumerWidget {
  const OnlineWorkCard({
    super.key,
    required this.work,
    required this.onTap,
    this.selected = false,
  });

  final OnlineWork work;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coverUrl = ref
        .watch(onlineClientProvider)
        .coverUrl(work.id, size: KikoeruClient.coverThumbSize);

    final subtitle = [
      if (work.circleName.isNotEmpty) work.circleName,
      if (work.dlCount > 0) '↓${formatOnlineCount(work.dlCount)}',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
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
          ],
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
