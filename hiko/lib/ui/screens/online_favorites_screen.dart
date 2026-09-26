import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/context_menu.dart';
import '../widgets/online_account_dialogs.dart';
import '../widgets/online_detail_panel.dart';
import '../widgets/online_work_grid.dart';
import '../widgets/toast.dart';

/// 在线收藏（1.93.0，裁决 Q3=A：侧边栏一级项）。
///
/// 数据全部来自 [onlineFavoritesProvider] 的本地索引 —— 索引在登录后一次性拉好
/// （见 `online_favorites.dart` 里为什么这么做），所以这里切歌单、翻页都不发请求，
/// 体感是瞬时的。代价是「别人在网页端改了我的歌单」要等一次刷新才同步，
/// 所以顶部留了显式的刷新入口。
///
/// 未登录时不隐藏这个视图（裁决里定的）：藏起来的话用户根本不知道有收藏这回事，
/// 进来看到登录引导反而更清楚。
class OnlineFavoritesScreen extends ConsumerStatefulWidget {
  const OnlineFavoritesScreen({
    super.key,
    required this.isMobile,
    this.onOpenBrowse,
  });

  final bool isMobile;

  /// 卡面标签被点击时切回「在线」浏览视图（筛选结果在那一页，见 [_filterByTag]）
  final VoidCallback? onOpenBrowse;

  @override
  ConsumerState<OnlineFavoritesScreen> createState() =>
      _OnlineFavoritesScreenState();
}

class _OnlineFavoritesScreenState extends ConsumerState<OnlineFavoritesScreen> {
  /// null = 「全部」；否则是歌单 UUID
  String? _playlistId;

  int _page = 1;
  int _pageSize = 60;

  int? _detailWorkId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ref.watch(onlineAccountProvider);
    final favorites = ref.watch(onlineFavoritesProvider);

    if (account.restoring) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!account.loggedIn) {
      return _LoginGuide(
        onLogin: () => unawaited(showOnlineLoginDialog(context)),
      );
    }

    final index = favorites.index;
    // 选中的歌单被删掉（或正在加载首个快照）时退回「全部」
    if (_playlistId != null &&
        index.playlists.isNotEmpty &&
        !index.playlists.any((p) => p.id == _playlistId)) {
      _playlistId = null;
      _page = 1;
    }

    final works = index.worksOf(_playlistId);
    final totalPages = works.isEmpty ? 0 : (works.length + _pageSize - 1) ~/ _pageSize;
    final page = totalPages == 0 ? 1 : _page.clamp(1, totalPages);
    final slice = works.isEmpty
        ? const <OnlineWork>[]
        : works.sublist(
            (page - 1) * _pageSize,
            (page * _pageSize).clamp(0, works.length),
          );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(theme, index, favorites),
              Expanded(
                child: _buildResults(
                  theme: theme,
                  favorites: favorites,
                  works: works,
                  slice: slice,
                ),
              ),
              if (works.isNotEmpty)
                OnlinePager(
                  page: page,
                  pageSize: _pageSize,
                  totalCount: works.length,
                  isMobile: widget.isMobile,
                  onPage: (target) => setState(
                    () => _page = target.clamp(1, totalPages),
                  ),
                  onPageSize: (size) => setState(() {
                    _pageSize = size;
                    _page = 1;
                  }),
                ),
            ],
          ),
        ),
        if (!widget.isMobile && _detailWorkId != null) ...[
          VerticalDivider(
            width: 1,
            color: theme.dividerColor.withValues(alpha: 0.4),
          ),
          SizedBox(
            width: 390,
            child: OnlineDetailPanel(
              workId: _detailWorkId!,
              onClose: () => setState(() => _detailWorkId = null),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------- 顶部

  Widget _buildHeader(
    ThemeData theme,
    OnlineFavorites index,
    OnlineFavoritesState favorites,
  ) {
    final pad = widget.isMobile ? 16.0 : 48.0;
    final selected = _playlistById(index, _playlistId);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 2, pad, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            '全部 ${index.countOf(null)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _playlistId == null,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => setState(() {
                            _playlistId = null;
                            _page = 1;
                          }),
                        ),
                      ),
                      for (final playlist in index.playlists)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            avatar: playlist.isSystem
                                ? Icon(
                                    playlist.isLiked
                                        ? Icons.favorite_rounded
                                        : Icons.bookmark_rounded,
                                    size: 12,
                                    color: playlist.isLiked
                                        ? const Color(0xFFD34C44)
                                        : null,
                                  )
                                : null,
                            label: Text(
                              '${playlist.displayName} ${index.countOf(playlist.id)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _playlistId == playlist.id,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() {
                              _playlistId = playlist.id;
                              _page = 1;
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 歌单管理：只在选中具体歌单、且它可改名/可删时出现
              if (selected != null && selected.editable)
                PopupMenuButton<String>(
                  tooltip: '管理歌单',
                  onSelected: (action) => unawaited(
                    action == 'rename'
                        ? renamePlaylistFlow(context, ref, selected)
                        : deletePlaylistFlow(context, ref, selected),
                  ),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'rename',
                      height: 36,
                      child: Text('重命名', style: TextStyle(fontSize: 12)),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      height: 36,
                      child: Text(
                        '删除歌单',
                        style: TextStyle(fontSize: 12, color: Color(0xFFD34C44)),
                      ),
                    ),
                  ],
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 20,
                    color: theme.hintColor,
                  ),
                ),
              IconButton(
                tooltip: '新建歌单',
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_createPlaylist()),
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
              IconButton(
                tooltip: '刷新收藏',
                visualDensity: VisualDensity.compact,
                onPressed: favorites.loading
                    ? null
                    : () => unawaited(
                          ref.read(onlineFavoritesProvider.notifier).refresh(),
                        ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _statusLine(index, favorites, selected),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  String _statusLine(
    OnlineFavorites index,
    OnlineFavoritesState favorites,
    OnlinePlaylist? selected,
  ) {
    if (favorites.error != null) return '同步失败：${favorites.error}';
    if (favorites.loading) return '正在同步歌单…';
    final scope = selected == null
        ? '全部歌单 · ${index.playlists.length} 个歌单'
        : '${selected.displayName} · ${selected.privacyLabel}';
    final hint = index.truncated ? ' · 作品过多，列表可能不全' : '';
    return '$scope$hint';
  }

  // ---------------------------------------------------------------- 结果

  Widget _buildResults({
    required ThemeData theme,
    required OnlineFavoritesState favorites,
    required List<OnlineWork> works,
    required List<OnlineWork> slice,
  }) {
    if (favorites.loading && favorites.index.playlists.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (favorites.error != null && favorites.index.playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 30, color: theme.hintColor),
              const SizedBox(height: 10),
              Text(
                '同步失败：${favorites.error}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () =>
                    unawaited(ref.read(onlineFavoritesProvider.notifier).refresh()),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (works.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded, size: 30, color: theme.hintColor),
            const SizedBox(height: 10),
            Text(
              _playlistId == null
                  ? '还没有收藏任何作品\n在在线作品的详情页点「收藏」就能加入歌单'
                  : '这个歌单还是空的',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.7, color: theme.hintColor),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 2,
          child: favorites.loading
              ? const LinearProgressIndicator(minHeight: 2)
              : null,
        ),
        Expanded(
          child: OnlineWorkGrid(
            works: slice,
            isMobile: widget.isMobile,
            selectedId: _detailWorkId,
            onTap: _openDetail,
            onContextMenu: _showWorkMenu,
            showTags: ref.watch(settingsProvider).showOnlineTags,
            onTagTap: _filterByTag,
          ),
        ),
      ],
    );
  }

  /// 收藏页的卡面标签点击（1.94.0 裁决 Q9=甲）。
  ///
  /// 结果列表在「在线」那一页，所以这里是「先应用筛选、再切视图」——
  /// 与浏览页同一套卡片、同一个标签，在一处能点另一处不能点会让人以为坏了。
  void _filterByTag(OnlineTag tag) {
    unawaited(ref.read(onlineBrowseProvider.notifier).selectTag(tag));
    widget.onOpenBrowse?.call();
  }

  // ---------------------------------------------------------------- 交互

  void _openDetail(OnlineWork work) {
    if (widget.isMobile) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OnlineDetailScreen(workId: work.id),
        ),
      );
      return;
    }
    setState(() => _detailWorkId = work.id);
  }

  /// 卡片右键 / 长按菜单。
  ///
  /// 「移出本歌单」只在选中具体歌单时出现 —— 在「全部」视图里说「本歌单」没有指代。
  /// 刻意**不做「移动」**：服务端只有 add / remove 两个端点，移动得拆成两次调用，
  /// 中途失败会留下「两边都在」的中间态。
  Future<void> _showWorkMenu(OnlineWork work, Offset position) async {
    final selected = _playlistId;
    final actions = <String, String>{
      'pick': '加入其它歌单…',
      if (selected != null) 'remove': '移出本歌单',
    };
    final action = await showHikoContextMenu<String>(
      context: context,
      position: position,
      items: [
        for (final entry in actions.entries)
          HikoContextMenuItem(
            value: entry.key,
            label: entry.value,
            icon: entry.key == 'remove'
                ? Icons.remove_circle_outline
                : Icons.playlist_add_rounded,
            isDestructive: entry.key == 'remove',
          ),
      ],
    );
    if (action == null || !mounted) return;

    if (action == 'pick') {
      await showPlaylistPicker(context, work: work);
      return;
    }
    if (action == 'remove' && selected != null) {
      final playlist = _playlistById(
        ref.read(onlineFavoritesProvider).index,
        selected,
      );
      final ok = await showConfirmDialog(
        context,
        title: '移出「${playlist?.displayName ?? '歌单'}」',
        message: '只是把《${work.title}》从这个歌单里移出，作品和其他歌单的记录都不受影响。',
        okLabel: '移出',
      );
      if (!ok || !mounted) return;
      await _removeFrom(selected, work);
    }
  }

  Future<void> _removeFrom(String playlistId, OnlineWork work) async {
    final client = ref.read(onlineClientProvider);
    try {
      await client.removeWorksFromPlaylist(playlistId, [work.id]);
      if (!mounted) return;
      ref.read(onlineFavoritesProvider.notifier).applyLocal(
            work: work,
            diff: PlaylistDiff(addTo: const [], removeFrom: [playlistId]),
          );
      showHikoToast(context, '已移出');
    } catch (e) {
      if (!mounted) return;
      showHikoToast(context, '移出失败：$e');
    }
  }

  Future<void> _createPlaylist() async {
    final name = await showPlaylistNameDialog(context);
    if (name == null || !mounted) return;
    try {
      final created =
          await ref.read(onlineClientProvider).createPlaylist(name: name);
      if (!mounted) return;
      ref.read(onlineFavoritesProvider.notifier).addPlaylist(created);
      setState(() {
        _playlistId = created.id;
        _page = 1;
      });
      showHikoToast(context, '已创建歌单「${created.displayName}」');
    } catch (e) {
      if (!mounted) return;
      showHikoToast(context, '新建失败：$e');
    }
  }
}

/// 在索引里按 id 找歌单；找不到（刚被删掉）返回 null
OnlinePlaylist? _playlistById(OnlineFavorites index, String? id) {
  if (id == null) return null;
  for (final playlist in index.playlists) {
    if (playlist.id == id) return playlist;
  }
  return null;
}

/// 未登录时的引导（在线收藏视图始终可达，进来才知道收藏需要账号）
class _LoginGuide extends StatelessWidget {
  const _LoginGuide({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border_rounded, size: 34, color: theme.hintColor),
            const SizedBox(height: 14),
            const Text(
              '在线收藏',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '收藏存在你的 asmr.one 账号里（歌单体系），\n'
              '登录后和网页版、手机版看到的是同一份。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, height: 1.8, color: theme.hintColor),
            ),
            const SizedBox(height: 6),
            Text(
              '可以按「未听 / 已听」这类状态建多个歌单来分类管理。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, height: 1.7, color: theme.hintColor),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login_rounded, size: 16),
              label: const Text('登录 asmr.one', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
