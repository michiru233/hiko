import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/kikoeru_client.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../widgets/online_cover.dart';
import '../widgets/online_detail_panel.dart';

/// 在线音声视图（Kikoeru / asmr.one）。
///
/// 三入口：热门（下载量）/ 最新（发售日）/ 搜索。数据完全来自远程服务，
/// 不进本地库——在线专辑只在播放时构造为内存态 `Album`（见 OnlinePlayback）。
///
/// 桌面端：左侧列表 + 右侧详情面板；移动端：详情走全屏页。
class OnlineScreen extends ConsumerStatefulWidget {
  const OnlineScreen({super.key, required this.isMobile});

  final bool isMobile;

  @override
  ConsumerState<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends ConsumerState<OnlineScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  int? _detailWorkId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybeLoadMore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureLoaded());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_maybeLoadMore);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 首次进入时自动拉一次热门榜；已有数据则不打扰（切走再切回不重新加载）
  void _ensureLoaded() {
    if (!mounted) return;
    final state = ref.read(onlineBrowseProvider);
    if (state.works.isEmpty && !state.loading) {
      unawaited(
        ref.read(onlineBrowseProvider.notifier).loadFeed(OnlineFeed.popular),
      );
    }
  }

  void _maybeLoadMore() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 900) {
      unawaited(ref.read(onlineBrowseProvider.notifier).loadMore());
    }
  }

  Future<void> _submitSearch(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty) {
      await ref.read(onlineBrowseProvider.notifier).loadFeed(OnlineFeed.popular);
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
            width: 400,
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
              for (final feed in [OnlineFeed.popular, OnlineFeed.latest])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(feed.label, style: const TextStyle(fontSize: 12)),
                    selected: state.feed == feed,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => unawaited(
                      ref.read(onlineBrowseProvider.notifier).loadFeed(feed),
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
                        .loadFeed(OnlineFeed.popular));
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

  /// 两行筛选/状态：热门·最新显示「只看带字幕」；搜索·标签显示排序与当前筛选
  Widget _buildFilterLine(OnlineBrowseState state, ThemeData theme) {
    final isFeed = state.feed == OnlineFeed.popular ||
        state.feed == OnlineFeed.latest;
    return Row(
      children: [
        if (isFeed)
          FilterChip(
            label: const Text('只看带字幕', style: TextStyle(fontSize: 11)),
            selected: state.subtitleOnly,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => unawaited(
              ref.read(onlineBrowseProvider.notifier).toggleSubtitleOnly(),
            ),
          ),
        if (!isFeed) ...[
          PopupMenuButton<OnlineOrder>(
            tooltip: '排序方式',
            onSelected: (order) => unawaited(
              ref.read(onlineBrowseProvider.notifier).setOrder(order),
            ),
            itemBuilder: (_) => [
              for (final order in OnlineOrder.values)
                PopupMenuItem(
                  value: order,
                  child: Text(order.label, style: const TextStyle(fontSize: 12)),
                ),
            ],
            child: Chip(
              label: Text(
                '${state.order.label}${state.descending ? ' ↓' : ' ↑'}',
                style: const TextStyle(fontSize: 11),
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            _statusLine(state),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
        ),
      ],
    );
  }

  String _statusLine(OnlineBrowseState state) {
    if (state.loading) return '正在连接在线服务器…';
    if (state.error != null) return '';
    final total = state.totalCount > 0 ? '共 ${formatOnlineCount(state.totalCount)} 件' : '';
    return switch (state.feed) {
      OnlineFeed.popular => '热门榜 · $total',
      OnlineFeed.latest => '最新上架 · $total',
      OnlineFeed.search => '搜索「${state.keyword}」 · $total',
      OnlineFeed.tag => '标签「${state.tag?.name ?? ''}」 · $total',
    };
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
              state.feed == OnlineFeed.search ? '没有找到匹配的作品' : '没有拿到数据',
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
          ],
        ),
      );
    }
    return _buildGrid(state);
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
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            // 封面正方形 + 两行标题 + 一行副标题，用固定高度避免不同标题把网格撑歪
            mainAxisExtent: cardWidth + 62,
          ),
          itemCount: state.works.length + (state.loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= state.works.length) {
              return const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
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
