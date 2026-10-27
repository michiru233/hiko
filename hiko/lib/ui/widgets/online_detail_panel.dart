import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/online/kikoeru_client.dart';
import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../../data/settings_store.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../playback/playback_controller.dart';
import '../../utils/time.dart';
import '../lyrics/drawer_lyrics_view.dart';
import '../transitions/fullscreen_player_route.dart';
import 'detail_kit.dart';
import '../m3e/m3e.dart';
import 'offline_download_dialog.dart';
import '../../data/online/offline_downloads.dart';
import 'online_account_dialogs.dart';
import 'online_cover.dart';
import 'online_tag_menu.dart';
import 'toast.dart';

/// 桌面端：在线作品详情（从右侧滑出的面板）。
///
/// 1.99.30 起外壳与本地 `DetailDrawer` 同语义：`surfaceContainerLow` 色调面 +
/// 海拔 3 投影 + `M3EIconButton` 关闭钮；玻璃边框与 σ55 氛围背板已退场。
/// 内容行仍待按 `detail_kit.dart` 的 M3E 版本统一（见覆盖审计 C-09）。
class OnlineDetailPanel extends ConsumerWidget {
  const OnlineDetailPanel({
    super.key,
    required this.workId,
    required this.onClose,
    this.onSelectTag,
    this.onSelectCreator,
    this.onOpenWork,
  });

  final int workId;
  final VoidCallback onClose;
  /// 点详情页的标签 → 按该标签筛选。
  /// 1.94.0 起直接传 [OnlineTag]（响应里本来就带 `id`），不再需要标签表反查
  final ValueChanged<OnlineTag>? onSelectTag;

  /// 点详情页的声优 / 社团胶囊 → 按其筛选（1.97.0）
  final ValueChanged<OnlineCreatorFilter>? onSelectCreator;

  /// 点语言版本胶囊 → 打开该版本的详情（1.99.2）。桌面端原地换面板。
  final ValueChanged<int>? onOpenWork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 1.99.30 M3E：不透明色调面（surfaceContainerLow）+ 海拔 3 投影，
    // 玻璃边框与 σ55 氛围背板一起退场（plan §9.1）
    return DecoratedBox(
      decoration: BoxDecoration(
        color: M3ETheme.of(context).colors.surfaceContainerLow,
        boxShadow: M3EElevation.shadow(
          M3EElevation.level3,
          M3ETheme.of(context).colors.shadow,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: OnlineDetailBody(
              // 换作品时重置 Tab 与折叠态（State 会随位置被复用）
              key: ValueKey<int>(workId),
              workId: workId,
              onSelectTag: onSelectTag,
              onSelectCreator: onSelectCreator,
              onOpenWork: onOpenWork,
            ),
          ),
          // 关闭按钮（M3E 色调圆钮，1.99.38 换 M3EIconButton）
          Positioned(
            right: 8,
            top: 8,
            child: M3EIconButton(
              icon: Icons.close_rounded,
              tooltip: '关闭',
              onPressed: onClose,
              backgroundColor:
                  M3ETheme.of(context).colors.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// 移动端：在线作品详情全屏页
class OnlineDetailScreen extends StatelessWidget {
  const OnlineDetailScreen({
    super.key,
    required this.workId,
    this.onSelectTag,
    this.onSelectCreator,
    this.onOpenWork,
  });

  final int workId;
  /// 点详情页的标签 → 按该标签筛选。
  /// 1.94.0 起直接传 [OnlineTag]（响应里本来就带 `id`），不再需要标签表反查
  final ValueChanged<OnlineTag>? onSelectTag;

  /// 点详情页的声优 / 社团胶囊 → 按其筛选（1.97.0）
  final ValueChanged<OnlineCreatorFilter>? onSelectCreator;

  /// 点语言版本胶囊 → 打开该版本的详情（1.99.2）。移动端在宿主里压栈。
  final ValueChanged<int>? onOpenWork;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 1.99.38：移动在线详情顶栏统一到 M3EAppBar（原 Material AppBar title 15sp）。
      appBar: M3EAppBar.small(
        topInset: MediaQuery.paddingOf(context).top,
        title: const Text('作品详情'),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        leading: M3EIconButton(
          icon: Icons.arrow_back_rounded,
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: OnlineDetailBody(
        key: ValueKey<int>(workId),
        workId: workId,
        onSelectTag: onSelectTag,
        onSelectCreator: onSelectCreator,
        onOpenWork: onOpenWork,
        interceptBack: true,
      ),
    );
  }
}

/// 详情主体：面板与全屏页共用。
///
/// 结构骨架对齐本地 `DetailDrawer`（裁决 Q8=B）：封面 → 眼眉胶囊 → 标题 →
/// 声优/社团行 → 胶囊 → 操作行 → 信息行 → 标签 → 双 Tab → 曲目树/歌词。
class OnlineDetailBody extends ConsumerStatefulWidget {
  const OnlineDetailBody({
    super.key,
    required this.workId,
    this.onSelectTag,
    this.onSelectCreator,
    this.onOpenWork,
    this.interceptBack = false,
  });

  final int workId;

  /// 在非根层时截获系统返回键 / `maybePop`，先退回上一层（1.99.51）。
  ///
  /// 只有移动端全屏页传 true：桌面面板不是一条路由，注册 PopScope 会去管
  /// 宿主路由的 popDisposition，容易误伤。
  /// 点详情页的标签 → 按该标签筛选。
  /// 1.94.0 起直接传 [OnlineTag]（响应里本来就带 `id`），不再需要标签表反查
  final ValueChanged<OnlineTag>? onSelectTag;

  /// 点详情页的声优 / 社团胶囊 → 按其筛选（1.97.0）
  final ValueChanged<OnlineCreatorFilter>? onSelectCreator;

  /// 点语言版本胶囊 → 打开该版本的详情（1.99.2）。null 时胶囊只展示不可点。
  final ValueChanged<int>? onOpenWork;

  /// 见 [OnlineDetailBody.interceptBack]
  final bool interceptBack;

  @override
  ConsumerState<OnlineDetailBody> createState() => _OnlineDetailBodyState();
}

class _OnlineDetailBodyState extends ConsumerState<OnlineDetailBody> {
  /// 0: 曲目列表, 1: 歌词字幕（裁决 Q12=A）
  int _tabIndex = 0;

  /// 当前所在目录栈（1.99.51 裁决：逐层进入，不再渲染整棵树）。
  ///
  /// 空 = 作品根层。面包屑、返回键、「跳到正在播放」三处都以它为准；
  /// 换层时整个列表重建（走 AnimatedSwitcher 的淡入），不做层级嵌套。
  final List<OnlineFolderNode> _path = <OnlineFolderNode>[];

  /// 正在播放的那一行，供「跳到正在播放」之后定位
  final GlobalKey _activeRowKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // 详情页文字倍率（1.96.0）作用域：包住整个面板（含 loading / error），
    // `detail_kit` 里的共用件从它取值 —— 本地详情抽屉不套这层，于是不受影响。
    // 注意作用域只有**后代**读得到：本 State 自己的 `context` 在它之上，
    // 所以面板自有的文字走下面的 `_textScale` getter。
    final body = HikoDetailTextScale(
      scale: _textScale,
      child: ref.watch(onlineDetailProvider(widget.workId)).when(
            loading: () => const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (error, _) => _ErrorView(
              message: '$error',
              onRetry: () =>
                  ref.invalidate(onlineDetailProvider(widget.workId)),
            ),
            data: (detail) => _buildContent(context, detail),
          ),
    );
    if (!widget.interceptBack) return body;
    return PopScope(
      // 根层放行（关闭详情页），非根层拦截 → 退回上一层
      canPop: _path.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_path.isNotEmpty) setState(() => _path.removeLast());
      },
      child: body,
    );
  }

  /// 面板文字倍率（1.96.0）。多处要用 —— `ref.watch` 同一 provider 会被
  /// Riverpod 合并成一次订阅，不必再缓存成字段。
  double get _textScale =>
      ref.watch(settingsProvider.select((s) => s.onlineDetailTextScale));

  /// 曲目标题独立字号（1.97.0）。`_trackRow` 在 build 途中调用，
  /// watch 的订阅时机没问题。
  double get _trackTitleFontSize => ref.watch(
      settingsProvider.select((s) => s.onlineTrackTitleFontSize));

  // ---------------------------------------------------------------- 主体

  Widget _buildContent(BuildContext context, OnlineDetail detail) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final work = detail.work;
    final audio = detail.audioTracks;
    final client = ref.watch(onlineClientProvider);
    // 被屏蔽的标签在这里只弱化、不隐藏（1.95.0 裁决 Q4=乙 / Q5=甲）
    final blockedIds = ref.watch(blockedTagIdsProvider);
    // 面板自有文字的缩放（1.96.0）—— 共用件自己从作用域取，这里取给标题/副标题用
    final textScale = _textScale;

    // 精确监听，避免 positionStream 高频更新导致整树重建（同本地抽屉）
    final albumId = ref.watch(playbackProvider.select((p) => p.album?.id));
    final currentUrl =
        ref.watch(playbackProvider.select((p) => p.currentTrack?.url));
    final isPlaying = ref.watch(playbackProvider.select((p) => p.playing));
    final hasLiveLyrics = ref.watch(lyricsProvider.select((l) => l.hasLyrics));

    final isCurrentWork = albumId == work.albumId;
    // 用 hash 而非数组下标定位当前行：在线有三种播放范围（整部 / 目录 / 叶子目录），
    // 下标互不对齐
    final currentHash = _hashOf(currentUrl);

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面（带投光阴影与精细圆角）
            Container(
              decoration: BoxDecoration(
                borderRadius: M3EShape.radius(M3EShape.lg),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: M3EShape.radius(M3EShape.lg),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: OnlineCover(url: client.coverMainUrl(work.id)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            // 眼眉胶囊：来源 · RJ 号（裁决 Q9=A，纯标识不可点）
            HikoEyebrowPill(label: '在线 · ${work.rjCode ?? '#${work.id}'}'),
            const SizedBox(height: 10),
            Text(
              work.title,
              style: M3ETheme.of(context)
                  .type
                  .scaled(M3ETypeRole.titleLarge, textScale)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle(work),
              style: M3ETheme.of(context)
                  .type
                  .scaled(M3ETypeRole.bodySmall, textScale)
                  .copyWith(
                    color: M3ETheme.of(context).colors.onSurfaceVariant,
                  ),
            ),
            // 社团（紫）/ 声优（蓝）胶囊：1.97.0 起可点 → 弹「按此筛选 / 复制名字」
            // （1.91 的裁决 Q9=A「纯展示不可点」被 1.97 的筛选需求推翻）
            if (work.circleName.isNotEmpty || work.vas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (work.circleName.isNotEmpty)
                    _creatorPill(
                      name: work.circleName,
                      kind: OnlineCreatorKind.circle,
                      color: M3ESemantic.circleTint,
                    ),
                  for (final name in work.vas)
                    _creatorPill(
                      name: name,
                      kind: OnlineCreatorKind.va,
                      color: M3ESemantic.voiceTint,
                    ),
                ],
              ),
            ],
            // 其他语言版本（1.99.2）：汉化版 / 原版跳转（对齐 asmr.one 网页端）
            if (work.otherEditions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final edition in work.otherEditions)
                    _EditionChip(
                      edition: edition,
                      onTap: widget.onOpenWork == null
                          ? null
                          : () => widget.onOpenWork!(edition.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _buildActions(context, detail),
            const SizedBox(height: 20),
            M3ECard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: <Widget>[
                  HikoDetailInfoRowM3E(
                    label: '总时长',
                    value: _durationText(work, audio.length),
                  ),
                  HikoDetailInfoRowM3E(
                    label: '发售日期',
                    value: formatOnlineDate(work.release).isEmpty
                        ? '未知'
                        : formatOnlineDate(work.release),
                  ),
                  HikoDetailInfoRowM3E(
                    label: '下载量',
                    value: formatOnlineCount(work.dlCount),
                  ),
                  HikoDetailInfoRowM3E(
                    label: '评分',
                    value: _ratingText(work),
                  ),
                ],
              ),
            ),
            if (work.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in work.tags)
                    HikoTagChip(
                      tag: t.name,
                      // 被屏蔽的标签照常显示、只弱化（1.95.0 裁决 Q5=甲 + Q4=乙）：
                      // 详情页是「我明确点进来看的这一个作品」，把它的标签藏掉
                      // 会让用户以为数据缺了
                      blocked: blockedIds.contains(t.id),
                      // 响应里带 id，直接拿去筛选（1.94.0 前要拿名字去标签表反查）
                      onTap: widget.onSelectTag == null || t.id <= 0
                          ? null
                          : () => widget.onSelectTag!(t),
                      onContextMenu: (position) => unawaited(
                        showOnlineTagMenu(
                          context: context,
                          ref: ref,
                          tag: t,
                          position: position,
                          onFilter: widget.onSelectTag == null
                              ? null
                              : () => widget.onSelectTag!(t),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            M3EButtonGroup(
              labels: <String>[
                '曲目列表 (${audio.length})',
                // 正在播且当前曲目有实时歌词时加圆点（旧 HikoTabButton 的 hasBadge）
                isCurrentWork && hasLiveLyrics ? '歌词字幕 ●' : '歌词字幕',
              ],
              selectedIndex: _tabIndex,
              onSelected: (index) => setState(() => _tabIndex = index),
            ),
            const SizedBox(height: 12),
            if (_tabIndex == 0) ...[
              _buildPathBar(
                detail,
                currentHash: currentHash,
                isCurrentWork: isCurrentWork,
              ),
              const SizedBox(height: 2),
              // 换层淡入（1.99.51）：用路径做 key，只让**新的这一层**淡入。
              // 不用 AnimatedSwitcher：它会把进出两层叠在一起，高度先跳再落；
              // 这里旧层直接消失、新层从 0 淡到 1，没有重叠。
              TweenAnimationBuilder<double>(
                key: ValueKey<String>(
                  '${widget.workId}/${_path.map((n) => n.title).join('/')}',
                ),
                tween: Tween<double>(begin: 0, end: 1),
                duration: M3ETheme.of(context).motion.duration(
                  M3ESpringType.effects,
                  M3ESpringSpeed.normal,
                ),
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: child,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildTrackList(
                    detail: detail,
                    currentHash: currentHash,
                    isCurrentWork: isCurrentWork,
                    isPlaying: isPlaying,
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 380, child: DrawerLyricsView()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 操作行

  Widget _buildActions(BuildContext context, OnlineDetail detail) {
    final work = detail.work;
    final audio = detail.audioTracks;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        M3EButton(
          label: audio.isEmpty ? '无可播放音轨' : '播放全部',
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: audio.isEmpty
              ? null
              : () => unawaited(_playFrom(detail: detail, queue: audio)),
        ),
        OnlineFavoriteButton(work: work),
        _OfflineActionButton(work: work, audio: audio),
        M3EButton(
          label: '在浏览器打开',
          variant: M3EButtonVariant.outlined,
          icon: const Icon(Icons.open_in_new_rounded),
          onPressed: () => unawaited(_openInBrowser(work)),
        ),
        M3EButton(
          label: '复制 RJ 号',
          variant: M3EButtonVariant.outlined,
          icon: const Icon(Icons.content_copy_rounded),
          onPressed: work.rjCode == null
              ? null
              : () => unawaited(_copyRj(work.rjCode!)),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 曲目树

  /// 当前层的节点（根层 = 作品树；进入目录后 = 该目录的 children）。
  List<OnlineNode> _currentNodes(OnlineDetail detail) =>
      _path.isEmpty ? detail.tree : _path.last.children;

  /// 同层有序列表：目录 → 音频 → 图片 → 文本/视频（见 [sortLevel]）。
  /// 空目录（fileCount == 0）不参与渲染 —— 点进去只会看到空。
  List<OnlineNode> _orderedLevel(OnlineDetail detail) => sortLevel(<OnlineNode>[
        for (final node in _currentNodes(detail))
          if (node is! OnlineFolderNode || node.fileCount > 0) node,
      ]);

  void _enterFolder(OnlineFolderNode node) {
    setState(() => _path.add(node));
  }

  void _goUp() {
    if (_path.isEmpty) return;
    setState(() => _path.removeLast());
  }

  /// 路径条第 [index] 段（0 = 根）→ 截断到那一层。
  void _jumpToLevel(int index) {
    if (index >= _path.length) return;
    setState(() => _path.removeRange(index, _path.length));
  }

  /// 「正在播放」胶囊：把路径栈换成目标曲目所在的目录链，再滚动定位。
  void _jumpToPlaying(OnlineDetail detail, String hash) {
    final chain = folderChainTo(detail.tree, hash);
    setState(() {
      _path
        ..clear()
        ..addAll(chain);
    });
    // 换层要等下一帧 build + layout 才生效，目标行那时才有 RenderObject
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToActiveRow();
    });
  }

  OnlineTrack? _trackWithHash(OnlineDetail detail, String hash) {
    for (final track in detail.tracks) {
      if (track.hash == hash) return track;
    }
    return null;
  }

  /// 路径条（1.99.51）：返回箭头 +「全部文件 › … › 当前层」+ 正在播放胶囊。
  ///
  /// 路径过长时**反向滚动**（`reverse: true`）—— 溢出时保住的是右端（当前层），
  /// 而不是把用户丢回「全部文件」。
  Widget _buildPathBar(
    OnlineDetail detail, {
    required String? currentHash,
    required bool isCurrentWork,
  }) {
    final colors = M3ETheme.of(context).colors;
    final type = M3ETheme.of(context).type;
    final scale = _textScale;

    final playing =
        isCurrentWork && currentHash != null
            ? _trackWithHash(detail, currentHash)
            : null;
    // 胶囊只在「歌不在当前层」时出现：在当前层时它就在下面高亮着，没必要重复
    final playingHere = currentHash != null &&
        _currentNodes(detail).any(
          (node) => node is OnlineFileNode && node.track.hash == currentHash,
        );

    TextStyle segStyle(bool current) =>
        type.scaled(M3ETypeRole.labelMedium, scale).copyWith(
              color: current ? colors.onSurface : colors.onSurfaceVariant,
              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            );

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          if (_path.isNotEmpty)
            M3EIconButton(
              icon: Icons.arrow_back_rounded,
              tooltip: '上一级',
              size: M3EIconButtonSize.small,
              onPressed: _goUp,
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                children: [
                  _pathChip(
                    label: '全部文件',
                    style: segStyle(_path.isEmpty),
                    onTap: _path.isEmpty ? null : () => _jumpToLevel(0),
                  ),
                  for (var i = 0; i < _path.length; i++) ...[
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: colors.outline,
                    ),
                    _pathChip(
                      label: _path[i].title,
                      style: segStyle(i == _path.length - 1),
                      onTap: i == _path.length - 1
                          ? null
                          : () => _jumpToLevel(i + 1),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (playing != null && !playingHere)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: M3EPressable(
                onTap: () => _jumpToPlaying(detail, currentHash!),
                borderRadius: M3EShape.radius(M3EShape.full),
                pressScale: 0.97,
                semanticLabel: '跳到正在播放的曲目',
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: M3EShape.radius(M3EShape.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          '正在播放 · ${onlineTrackDisplayName(playing.title)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              type.scaled(M3ETypeRole.labelSmall, scale).copyWith(
                                    color: colors.onSecondaryContainer,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pathChip({
    required String label,
    required TextStyle style,
    required VoidCallback? onTap,
  }) {
    return M3EPressable(
      onTap: onTap,
      borderRadius: M3EShape.radius(M3EShape.sm),
      pressScale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTrackList({
    required OnlineDetail detail,
    required String? currentHash,
    required bool isCurrentWork,
    required bool isPlaying,
  }) {
    // 服务端没给层级时退化成单层列表（1.99.18 的兜底），仍按同一套排序
    final level = detail.tree.isEmpty
        ? sortLevel(<OnlineNode>[
            for (final track in detail.tracks) OnlineFileNode(track),
          ])
        : _orderedLevel(detail);

    if (level.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            _path.isEmpty ? '服务器未返回文件' : '这个目录是空的',
            style: M3ETheme.of(context)
                .type
                .scaled(M3ETypeRole.bodySmall, _textScale)
                .copyWith(
                  color: M3ETheme.of(context).colors.onSurfaceVariant,
                ),
          ),
        ),
      ];
    }

    final out = <Widget>[];
    // 序号按**当前层**的音频重新计数：进入「本編」后从 01 开始，
    // 与这一层的播放队列（groupOf）同一套编号
    var seq = 0;
    for (final node in level) {
      switch (node) {
        case OnlineFolderNode():
          final playable = playableIn(node);
          out.add(
            _FolderRow(
              title: node.title,
              itemCount: node.fileCount,
              totalSeconds: node.totalSeconds,
              onOpen: () => _enterFolder(node),
              onPlay: playable.isEmpty
                  ? null
                  : () => unawaited(
                        _playFrom(detail: detail, queue: playable),
                      ),
            ),
          );
        case OnlineFileNode(:final track):
          if (track.playable) {
            seq++;
            out.add(
              _trackRow(
                detail,
                track,
                index: seq,
                currentHash: currentHash,
                isCurrentWork: isCurrentWork,
                isPlaying: isPlaying,
              ),
            );
          } else {
            out.add(_fileRow(track));
          }
      }
    }
    return out;
  }

  Widget _trackRow(
    OnlineDetail detail,
    OnlineTrack track, {
    required int index,
    required String? currentHash,
    required bool isCurrentWork,
    required bool isPlaying,
  }) {
    final active = isCurrentWork && currentHash == track.hash;
    return HikoTrackRowM3E(
      // 当前行挂全局 key，供「自动滚到正在播放的那一行」定位（裁决 Q2）。
      // 同一时刻只可能有一行 active，所以这个 key 不会撞。
      key: active ? _activeRowKey : null,
      index: index,
      name: onlineTrackDisplayName(track.title),
      durationSeconds: track.duration,
      active: active,
      playing: active && isPlaying,
      indent: 0,
      // 曲目标题独立字号（1.97.0）：绝对值，不乘详情倍率 —— 见 HikoTrackRow 注释
      titleFontSize: _trackTitleFontSize,
      trailing: track.lyricsHash == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 6, right: 8),
              child: Icon(
                Icons.subtitles_outlined,
                size: 13,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
      onTap: () => _onTrackTap(
        detail,
        track,
        active: active,
        isPlaying: isPlaying,
      ),
    );
  }

  // ---------------------------------------------------------------- 非音频文件行

  /// 图片 / 文本 / 视频行（1.99.18，对齐 asmr.one 的文件树）。
  /// 点击按类型分流：图片 → 应用内预览；文本 → 查看对话框；视频 → 跳浏览器。
  Widget _fileRow(OnlineTrack track) {
    return _FileRow(
      track: track,
      onTap: () {
        if (track.isImage) {
          unawaited(_showImageViewer(track));
        } else if (track.isText) {
          unawaited(_showTextDialog(track));
        } else {
          unawaited(_openExternally(track));
        }
      },
    );
  }

  /// 图片全屏预览：InteractiveViewer 捏合/双击缩放；封面缓存管线复用
  /// （`streamUrl(hash)` 与字幕同一套媒体流端点，带服务端时效签名）。
  Future<void> _showImageViewer(OnlineTrack track) async {
    final url = ref.read(onlineClientProvider).streamUrl(track.hash);
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(
            onlineTrackDisplayName(track.title),
            style: const M3EType().bodyMedium,
          ),
        ),
        body: InteractiveViewer(
          maxScale: 8,
          child: Center(child: OnlineCover(url: url, fit: BoxFit.contain)),
        ),
      ),
    );
  }

  /// 文本文件轻量查看（未配对成字幕的散件：说明 txt、汉化对照等）
  Future<void> _showTextDialog(OnlineTrack track) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final text = await ref.read(onlineClientProvider).fetchText(track.hash);
    if (!mounted) return;
    if (text == null) {
      messenger?.showSnackBar(const SnackBar(content: Text('无法加载文件内容')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = M3ETheme.of(ctx);
        return M3EDialog(
          maxWidth: 520,
          title: onlineTrackDisplayName(track.title),
          content: SizedBox(
            height: 360,
            child: SingleChildScrollView(
              child: SelectableText(
                text,
                style: theme.type.bodyMedium,
              ),
            ),
          ),
          actions: <Widget>[
            M3EButton(
              label: '关闭',
              variant: M3EButtonVariant.text,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }

  /// 视频等其余类型：应用内是音频引擎，交给系统浏览器/播放器
  Future<void> _openExternally(OnlineTrack track) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final url = ref.read(onlineClientProvider).streamUrl(track.hash);
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        messenger?.showSnackBar(SnackBar(content: Text('无法打开：$url')));
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('无法打开浏览器：$e')));
    }
  }

  /// 把当前播放行滚进视野（停在视口上三分之一处，上下都留出上下文）。
  ///
  /// 行不存在时静默跳过：歌词页未渲染曲目、或服务端把该曲目从树里剔除了，
  /// 都不该影响别的逻辑。
  void _scrollToActiveRow() {
    final target = _activeRowKey.currentContext;
    if (target == null) return;
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: M3ETheme.of(context)
            .motion
            .duration(M3ESpringType.spatial, M3ESpringSpeed.normal),
        curve: M3ETheme.of(context).motion.fallbackCurve,
        alignment: 0.35,
      ),
    );
  }

  // ---------------------------------------------------------------- 交互

  /// 创作者胶囊 + 它的菜单（1.99.48：仓库里最后一处 `showMenu` 收口）。
  ///
  /// 以前是 `showMenu` + 三个 36dp / 12sp 的 `PopupMenuItem`，属于审计 D-05
  /// 记的「三套菜单规格」之一。现在锚点、面板材质、行高、键盘都由
  /// `M3EMenu` 负责，这里只声明三条动作：筛选、复制、屏蔽（destructive）。
  ///
  /// 没有 `onSelectCreator` 时胶囊不可点、也不出菜单 —— 与 1.97.0 的行为一致：
  /// 只有「能筛选」的面才把这三个动作当作可用集合。
  Widget _creatorPill({
    required String name,
    required OnlineCreatorKind kind,
    required Color color,
  }) {
    final isVa = kind == OnlineCreatorKind.va;
    final enabled = widget.onSelectCreator != null;
    return M3EMenu(
      minWidth: 168,
      maxWidth: 240,
      builder: (context, controller, _) => HikoPersonPill(
        name: name,
        color: color,
        onTap: enabled ? () => controller.open() : null,
      ),
      children: <Widget>[
        M3EMenuAction(
          label: isVa ? '按此声优筛选' : '按此社团筛选',
          leadingIcon: Icons.filter_alt_outlined,
          onPressed: () => widget.onSelectCreator!(
            OnlineCreatorFilter(kind: kind, name: name),
          ),
        ),
        M3EMenuAction(
          label: '复制名字',
          leadingIcon: Icons.copy_rounded,
          onPressed: () => unawaited(_copyCreatorName(name)),
        ),
        M3EMenuAction(
          label: isVa ? '屏蔽此声优' : '屏蔽此社团',
          leadingIcon: Icons.block_rounded,
          destructive: true,
          onPressed: () => unawaited(_blockCreator(name: name, kind: kind)),
        ),
      ],
    );
  }

  Future<void> _copyCreatorName(String name) async {
    await Clipboard.setData(ClipboardData(text: name));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('已复制 $name')));
  }

  /// 声优 / 社团黑名单（1.99.3）：与标签黑名单同一套机制，
  /// 编进搜索关键字在服务端过滤；管理入口在设置 → 在线账号的黑名单对话框。
  Future<void> _blockCreator({
    required String name,
    required OnlineCreatorKind kind,
  }) async {
    final isVa = kind == OnlineCreatorKind.va;
    await ref.read(settingsProvider.notifier).addBlockedCreator(
          OnlineCreatorBlock(
            kind: isVa
                ? OnlineCreatorBlock.kindVa
                : OnlineCreatorBlock.kindCircle,
            name: name,
          ),
        );
    if (!mounted) return;
    showHikoToast(
      context,
      '已屏蔽${isVa ? '声优' : '社团'}「$name」，浏览与搜索不再出现 TA 的作品',
    );
  }

  void _onTrackTap(
    OnlineDetail detail,
    OnlineTrack track, {
    required bool active,
    required bool isPlaying,
  }) {
    if (active) {
      // 点当前曲目不打断播放（同本地 1.79）：暂停中恢复播放，播放中直接进播放页
      if (!isPlaying) ref.read(playbackProvider.notifier).toggle();
      _openPlayer();
      return;
    }
    unawaited(
      _playFrom(
        detail: detail,
        // 裁决 Q5=C：点单曲 = 该曲所在叶子目录内的队列，不跨目录接续
        queue: detail.groupOf(track),
        start: track,
        openPlayer: true,
      ),
    );
  }

  Future<void> _playFrom({
    required OnlineDetail detail,
    required List<OnlineTrack> queue,
    OnlineTrack? start,
    bool openPlayer = false,
  }) async {
    if (queue.isEmpty) return;
    var index = 0;
    if (start != null) {
      final found = queue.indexWhere((t) => t.hash == start.hash);
      if (found >= 0) index = found;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final error = await ref.read(onlinePlaybackProvider).play(
          detail.work,
          queue,
          startIndex: index,
          // 在线队列快照：供「专辑循环」跨作品接续时定位相邻作品
          queue: ref.read(onlineBrowseProvider).works,
        );
    if (error != null) {
      messenger?.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (openPlayer) _openPlayer();
  }

  void _openPlayer() {
    if (!mounted) return;
    Navigator.of(context).push(FullscreenPlayerRoute());
  }

  Future<void> _openInBrowser(OnlineWork work) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // API 域名 ≠ 网页域名（官方实例 api.asmr.one/works/{id} 实测 404）
    final url = ref.read(onlineClientProvider).workPageUrl(work.id);
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) messenger?.showSnackBar(SnackBar(content: Text('无法打开：$url')));
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('无法打开浏览器：$e')));
    }
  }

  Future<void> _copyRj(String rjCode) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: rjCode));
    messenger?.showSnackBar(SnackBar(content: Text('已复制 $rjCode')));
  }

  // ---------------------------------------------------------------- 文案

  static String _subtitle(OnlineWork work) {
    final voices = work.vas.isEmpty ? '未标注声优' : work.vas.join('・');
    final circle = work.circleName.isEmpty ? '未知社团' : work.circleName;
    return '$voices · $circle';
  }

  static String _durationText(OnlineWork work, int count) {
    final base = '$count 首';
    return work.durationSeconds > 0
        ? '$base · ${formatDuration(work.durationSeconds.toDouble())}'
        : base;
  }

  static String _ratingText(OnlineWork work) => work.rateCount > 0
      ? '${work.rateAverage} / 5（${work.rateCount} 评）'
      : '暂无评分';

  /// 从播放 URL 反解 hash（流播 URL 或缓存文件名两种形态都吃）
  static String? _hashOf(String? url) =>
      url == null ? null : KikoeruClient.hashFromPlaybackUrl(url);
}

/// 详情页的收藏按钮（裁决 Q5=A）。
///
/// 三种形态：
/// - **未登录**：置灰（恢复流程未结束时更是直接禁用），点了弹登录引导
/// - **已登录但不在任何歌单里**：普通描边胶囊「收藏」
/// - **已在歌单里**：红图标 + 红字 + 红色描边与底色，标题里直接写出歌单名 ——
///   只点亮图标的话，「收藏到哪个歌单了」还得点进去才知道
///
/// 点击动作统一是打开多选歌单菜单（裁决 Q8=B），不做「点一下无脑塞进我喜欢的」：
/// 用户明确要求收藏要能分类（「未听」「已听」），一键默认值反而会污染默认歌单。
class OnlineFavoriteButton extends ConsumerWidget {
  const OnlineFavoriteButton({super.key, required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final account = ref.watch(onlineAccountProvider);
    final index = ref.watch(onlineFavoritesProvider).index;

    if (!account.loggedIn) {
      return M3EButton(
        label: '收藏',
        variant: M3EButtonVariant.outlined,
        icon: const Icon(Icons.bookmark_border_rounded),
        // 恢复登录态期间禁用：否则冷启动那一下会闪出「去登录」，
        // 而用户其实早就登录了
        onPressed: account.settled
            ? () => unawaited(
                  showLoginRequiredDialog(context, action: '收藏作品'),
                )
            : null,
      );
    }

    final collected = index.playlistsOf(work.id);
    final names = [
      for (final playlist in index.playlists)
        if (collected.contains(playlist.id)) playlist.displayName,
    ];
    final label = switch (names.length) {
      0 => '收藏',
      1 => '已收藏 · ${names.first}',
      _ => '已收藏 · ${names.length} 个歌单',
    };
    final highlighted = names.isNotEmpty;

    final button = M3EButton(
      label: label,
      variant: M3EButtonVariant.outlined,
      icon: Icon(
        highlighted
            ? Icons.bookmark_rounded
            : Icons.bookmark_border_rounded,
      ),
      // 已收藏：用品牌红整颗点亮（语义色表达不了「收藏」的红色语义）
      backgroundColor: highlighted
          ? M3ESemantic.favorite.withValues(alpha: isDark ? 0.16 : 0.08)
          : null,
      foregroundColor: highlighted ? M3ESemantic.favorite : null,
      borderColor:
          highlighted ? M3ESemantic.favorite.withValues(alpha: 0.5) : null,
      onPressed: () => unawaited(showPlaylistPicker(context, work: work)),
    );
    if (names.isEmpty) return button;
    return Tooltip(message: '已在：${names.join('、')}', child: button);
  }
}

/// 目录行（裁决 Q14=C）：折叠三角 + 文件夹名 + 「N 个项目 · 总时长」，
/// hover 时右侧换成播放图标（播放该目录下的全部音频）。
/// 语言版本胶囊（1.99.2）：翻译图标 + 语言名，点按跳到该版本详情。
///
/// 汉化版是主场景（asmr.one 网页端同款入口）；从汉化版跳回原版时
/// 标注「原版」，不然用户不知道「日本語」这颗胶囊是回去的路。
class _EditionChip extends StatelessWidget {
  const _EditionChip({required this.edition, this.onTap});

  final OnlineWorkEdition edition;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = edition.isOriginal
        ? '${edition.lang}（原版）'
        : edition.lang;
    return Tooltip(
      message: onTap == null ? label : '查看$label版本',
      child: InkWell(
        onTap: onTap,
        borderRadius: M3EShape.radius(M3EShape.full),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: M3EShape.radius(M3EShape.full),
            border: Border.all(
              color: theme.colorScheme.onSurfaceVariant
                  .withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.translate_rounded,
                size: 13,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const M3EType().labelMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 目录行（1.99.51）：点击 = 进入该目录；右侧常驻「播放全部」+ 进入箭头。
///
/// 行高 56，与音频行同一节奏。图标装进 32dp 的 `tertiaryContainer` 方块 ——
/// 目录是**结构**不是状态：`secondaryContainer` 已经被「选中 / 播放中」占用，
/// 而 1.99.48 之前借的琥珀金是「评分」的语义。
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.title,
    required this.itemCount,
    required this.totalSeconds,
    required this.onOpen,
    this.onPlay,
  });

  final String title;
  final int itemCount;
  final double totalSeconds;
  final VoidCallback onOpen;

  /// 子树里没有可播放音频时为 null（纯图片目录），不出播放键
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final type = m3e.type;
    final scale = HikoDetailTextScale.of(context);
    final meta = '$itemCount 项'
        '${totalSeconds > 0 ? ' · ${formatDuration(totalSeconds)}' : ''}';

    return M3EPressable(
      onTap: onOpen,
      borderRadius: M3EShape.radius(M3EShape.md),
      pressScale: 0.99,
      semanticLabel: '进入目录 $title',
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colors.tertiaryContainer,
                borderRadius: M3EShape.radius(M3EShape.sm),
              ),
              child: Icon(
                Icons.folder_rounded,
                size: 18,
                color: colors.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.scaled(M3ETypeRole.labelLarge, scale).copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    style: type.scaled(M3ETypeRole.labelSmall, scale).copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ],
              ),
            ),
            if (onPlay != null)
              M3EIconButton(
                icon: Icons.play_circle_outline_rounded,
                tooltip: '播放该目录',
                size: M3EIconButtonSize.small,
                onPressed: onPlay,
              ),
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 非音频文件行（1.99.18 起，1.99.51 对齐 56dp）：图片带缩略图
/// （`streamUrl(hash)` + 封面缓存管线），文本 / 视频带类型图标；尾部显示体积
/// 与动作。缩略图沿用 [OnlineCover] 的防社手模糊行为 —— 隐私模式开着时同样糊掉。
class _FileRow extends ConsumerWidget {
  const _FileRow({required this.track, required this.onTap});

  final OnlineTrack track;
  final VoidCallback onTap;

  static String _sizeLabel(int b) {
    if (b <= 0) return '';
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final type = m3e.type;
    final scale = HikoDetailTextScale.of(context);
    final size = _sizeLabel(track.size);

    final Widget leading = track.isImage
        ? ClipRRect(
            borderRadius: M3EShape.radius(M3EShape.sm),
            child: SizedBox(
              width: 32,
              height: 32,
              child: OnlineCover(
                url: ref.watch(onlineClientProvider).streamUrl(track.hash),
              ),
            ),
          )
        : Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: M3EShape.radius(M3EShape.sm),
            ),
            child: Icon(
              track.isText ? Icons.description_rounded : Icons.movie_rounded,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          );

    return M3EPressable(
      onTap: onTap,
      borderRadius: M3EShape.radius(M3EShape.md),
      pressScale: 0.99,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                onlineTrackDisplayName(track.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.scaled(M3ETypeRole.bodyMedium, scale).copyWith(
                      color: colors.onSurface,
                    ),
              ),
            ),
            if (size.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(
                size,
                style: type.scaled(M3ETypeRole.labelSmall, scale).copyWith(
                      color: colors.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
              ),
            ],
            const SizedBox(width: 10),
            Icon(
              track.isImage
                  ? Icons.image_outlined
                  : track.isText
                      ? Icons.notes_rounded
                      : Icons.open_in_new_rounded,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 30, color: M3ETheme.of(context).colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: M3ETheme.of(context)
                  .type
                  .scaled(
                    M3ETypeRole.bodySmall,
                    HikoDetailTextScale.of(context),
                  )
                  .copyWith(
                    color: M3ETheme.of(context).colors.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            M3EButton(
              label: '重试',
              variant: M3EButtonVariant.outlined,
              size: M3EButtonSize.small,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// 离线下载状态按钮（1.99.16）：未离线→勾选对话框；排队/下载中→取消；
/// 已离线→确认删除（缓存文件 + 离线索引一并移除）。
class _OfflineActionButton extends ConsumerWidget {
  const _OfflineActionButton({required this.work, required this.audio});

  final OnlineWork work;
  final List<OnlineTrack> audio;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(offlineDownloadProvider)[work.id];
    final offlineWorks = ref.watch(offlineIndexListProvider);
    final isOffline = offlineWorks.any((e) => e.workId == work.id);

    final (label, icon, onPressed_) = switch (downloadState) {
      DownloadRunning(:final done, :final total) => (
          '下载中 $done/$total',
          Icons.downloading_rounded,
          () => unawaited(
              ref.read(offlineDownloadProvider.notifier).cancel(work.id)),
        ),
      DownloadQueued() => (
          '排队中',
          Icons.schedule_rounded,
          () => unawaited(
              ref.read(offlineDownloadProvider.notifier).cancel(work.id)),
        ),
      DownloadFailed(:final message) => (
          '下载失败',
          Icons.error_outline_rounded,
          () => showHikoToast(context, message),
        ),
      _ when isOffline => (
          '已离线',
          Icons.download_done_rounded,
          () => unawaited(_confirmRemove(context, ref)),
        ),
      _ => (
          '离线下载',
          Icons.download_rounded,
          audio.isEmpty
              ? null
              : () => OfflineDownloadDialog.show(context, work: work, audio: audio),
        ),
    };

    return M3EButton(
      label: label,
      variant: M3EButtonVariant.outlined,
      icon: Icon(icon),
      onPressed: onPressed_,
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = M3ETheme.of(ctx);
        return M3EDialog(
          title: '删除离线内容',
          content: Text(
            '将删除该作品已下载的音轨、字幕与封面缓存，'
            '再次收听需要重新联网。确认删除？',
            style: theme.type.bodyMedium.copyWith(
              color: theme.colors.onSurfaceVariant,
            ),
          ),
          actions: <Widget>[
            M3EButton(
              label: '取消',
              variant: M3EButtonVariant.text,
              onPressed: () => Navigator.pop(ctx, false),
            ),
            M3EButton(
              label: '删除',
              variant: M3EButtonVariant.destructive,
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await ref.read(onlineAudioCacheProvider).removeWork(work.id);
    await ref.read(offlineIndexListProvider.notifier).remove(work.id);
    if (context.mounted) showHikoToast(context, '已删除离线内容');
  }
}
