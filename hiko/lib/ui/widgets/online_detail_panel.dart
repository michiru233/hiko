import 'dart:async';
import 'dart:ui';

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
import '../theme.dart';
import '../transitions/fullscreen_player_route.dart';
import 'detail_kit.dart';
import 'online_account_dialogs.dart';
import 'online_cover.dart';
import 'online_tag_menu.dart';

/// 桌面端：在线作品详情（从右侧滑出的面板）。
///
/// 1.91.0 起外壳与本地 `DetailDrawer` 完全一致（裁决 Q1/Q8=B）：
/// 实底 + 左边框 + 大投影 + 封面虚化氛围背板 + 右上角悬浮玻璃关闭钮。
/// 视觉数值一律取自 `detail_kit.dart`，两处详情页共用同一份实现。
class OnlineDetailPanel extends ConsumerWidget {
  const OnlineDetailPanel({
    super.key,
    required this.workId,
    required this.onClose,
    this.onSelectTag,
    this.onSelectCreator,
  });

  final int workId;
  final VoidCallback onClose;
  /// 点详情页的标签 → 按该标签筛选。
  /// 1.94.0 起直接传 [OnlineTag]（响应里本来就带 `id`），不再需要标签表反查
  final ValueChanged<OnlineTag>? onSelectTag;

  /// 点详情页的声优 / 社团胶囊 → 按其筛选（1.97.0）
  final ValueChanged<OnlineCreatorFilter>? onSelectCreator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 氛围背板的底图：整块被 σ55 糊掉，只留色块，不构成隐私风险。
    // 与详情大图共用同一个 URL —— 磁盘缓存只存一份
    final coverUrl = ref.watch(onlineClientProvider).coverMainUrl(workId);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? HikoColors.darkBg : HikoColors.lightBg,
        border: Border(
          left: BorderSide(
            color:
                isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorder,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
            blurRadius: 40,
            offset: const Offset(-15, 0),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 沉浸式虚化封面氛围背板（与本地抽屉同参数）
          Positioned(
            top: -60,
            right: -60,
            width: 320,
            height: 320,
            child: IgnorePointer(
              child: Opacity(
                opacity: isDark ? 0.10 : 0.07,
                // RepaintBoundary（1.88.1 硬约束）：σ55 里层还套着 OnlineCover
                // 自己的 σ20，不隔离就会在父级每次重绘时把两层高斯都重算一遍。
                child: RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                    child: OnlineCover(url: coverUrl),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: OnlineDetailBody(
              // 换作品时重置 Tab 与折叠态（State 会随位置被复用）
              key: ValueKey<int>(workId),
              workId: workId,
              onSelectTag: onSelectTag,
              onSelectCreator: onSelectCreator,
            ),
          ),
          // 关闭按钮（玻璃悬浮微圆角）
          Positioned(
            right: 14,
            top: 14,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ),
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
  });

  final int workId;
  /// 点详情页的标签 → 按该标签筛选。
  /// 1.94.0 起直接传 [OnlineTag]（响应里本来就带 `id`），不再需要标签表反查
  final ValueChanged<OnlineTag>? onSelectTag;

  /// 点详情页的声优 / 社团胶囊 → 按其筛选（1.97.0）
  final ValueChanged<OnlineCreatorFilter>? onSelectCreator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作品详情', style: TextStyle(fontSize: 15)),
      ),
      body: OnlineDetailBody(
        key: ValueKey<int>(workId),
        workId: workId,
        onSelectTag: onSelectTag,
        onSelectCreator: onSelectCreator,
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
  });

  final int workId;
  /// 点详情页的标签 → 按该标签筛选。
  /// 1.94.0 起直接传 [OnlineTag]（响应里本来就带 `id`），不再需要标签表反查
  final ValueChanged<OnlineTag>? onSelectTag;

  /// 点详情页的声优 / 社团胶囊 → 按其筛选（1.97.0）
  final ValueChanged<OnlineCreatorFilter>? onSelectCreator;

  @override
  ConsumerState<OnlineDetailBody> createState() => _OnlineDetailBodyState();
}

class _OnlineDetailBodyState extends ConsumerState<OnlineDetailBody> {
  /// 0: 曲目列表, 1: 歌词字幕（裁决 Q12=A）
  int _tabIndex = 0;

  /// **已展开**的目录路径键。初始为空集 = 全部折叠（裁决 Q9 改判）。
  ///
  /// 1.91.0 用的是「已折叠」集合 + 默认全展开；1.92.0 反过来 ——
  /// 展开这个动作交给用户，比替他猜「哪个目录值得开」更省事，
  /// 也顺带消掉了「第一个目录没有直属音频」那条边角规则。
  final Set<String> _expanded = <String>{};

  /// 正在播放的那一行，供自动滚动定位
  final GlobalKey _activeRowKey = GlobalKey();

  /// 已经自动展开过的曲目 hash。两重作用：
  /// ① 同一首不会反复触发；② 用户手动把它折回去后，下一帧不会被强行再打开。
  String? _revealedHash;

  @override
  Widget build(BuildContext context) {
    // 详情页文字倍率（1.96.0）作用域：包住整个面板（含 loading / error），
    // `detail_kit` 里的共用件从它取值 —— 本地详情抽屉不套这层，于是不受影响。
    // 注意作用域只有**后代**读得到：本 State 自己的 `context` 在它之上，
    // 所以面板自有的文字走下面的 `_textScale` getter。
    return HikoDetailTextScale(
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

    final folderKeys = folderKeysIn(detail.tree);
    // 用 every 而不是比长度：`_expanded` 里理论上不会留文件夹之外的键，
    // 但「长度相等 ≠ 全展开」这种不变量没必要靠约定维持。
    final allExpanded =
        folderKeys.isNotEmpty && folderKeys.every(_expanded.contains);

    // 裁决 Q2：正在播的那一行必须看得见。默认全折叠之后这条更必要 ——
    // 切歌切进别的目录，当前行会彻底隐形。
    _maybeRevealPlaying(
      detail: detail,
      isCurrentWork: isCurrentWork,
      hash: currentHash,
    );

    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面（带投光阴影与精细圆角）
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                    blurRadius: 26,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
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
              style: TextStyle(
                fontSize: 22 * textScale,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle(work),
              style: TextStyle(
                fontSize: 12 * textScale,
                color: theme.hintColor,
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
                    Builder(
                      builder: (pillContext) => HikoPersonPill(
                        name: work.circleName,
                        color: hikoCircleColor,
                        onTap: widget.onSelectCreator == null
                            ? null
                            : () => unawaited(_showCreatorMenu(
                                  pillContext,
                                  name: work.circleName,
                                  kind: OnlineCreatorKind.circle,
                                )),
                      ),
                    ),
                  for (final name in work.vas)
                    Builder(
                      builder: (pillContext) => HikoPersonPill(
                        name: name,
                        color: hikoVoiceColor,
                        onTap: widget.onSelectCreator == null
                            ? null
                            : () => unawaited(_showCreatorMenu(
                                  pillContext,
                                  name: name,
                                  kind: OnlineCreatorKind.va,
                                )),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _buildActions(context, detail, folderKeys, allExpanded),
            const SizedBox(height: 20),
            HikoInfoRow(
              label: '总时长',
              value: _durationText(work, audio.length),
            ),
            HikoInfoRow(
              label: '发售日期',
              value: formatOnlineDate(work.release).isEmpty
                  ? '未知'
                  : formatOnlineDate(work.release),
            ),
            HikoInfoRow(label: '下载量', value: formatOnlineCount(work.dlCount)),
            HikoInfoRow(label: '评分', value: _ratingText(work)),
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
            HikoSegmentedTabs(
              left: HikoTabButton(
                label: '曲目列表 (${audio.length})',
                icon: Icons.format_list_bulleted_rounded,
                selected: _tabIndex == 0,
                onTap: () => setState(() => _tabIndex = 0),
              ),
              right: HikoTabButton(
                label: '歌词字幕',
                icon: Icons.subtitles_rounded,
                hasBadge: isCurrentWork && hasLiveLyrics,
                selected: _tabIndex == 1,
                onTap: () => setState(() => _tabIndex = 1),
              ),
            ),
            const SizedBox(height: 14),
            if (_tabIndex == 0)
              ..._buildTrackList(
                detail: detail,
                currentHash: currentHash,
                isCurrentWork: isCurrentWork,
                isPlaying: isPlaying,
              )
            else
              const SizedBox(height: 380, child: DrawerLyricsView()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 操作行

  Widget _buildActions(
    BuildContext context,
    OnlineDetail detail,
    List<String> folderKeys,
    bool allExpanded,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final work = detail.work;
    final audio = detail.audioTracks;
    final textScale = _textScale;
    // 按钮文字跟着详情倍率走 —— 但按钮的内边距不跟着变：
    // 它们是固定几何（`hikoOutlinedPillStyle`），跟着变会让胶囊高矮不一
    final actionStyle = TextStyle(fontSize: 11 * textScale);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          style: hikoFilledPillStyle(),
          onPressed: audio.isEmpty
              ? null
              : () => unawaited(_playFrom(detail: detail, queue: audio)),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(
            audio.isEmpty ? '无可播放音轨' : '播放全部',
            style: TextStyle(
              fontSize: 12 * textScale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        OnlineFavoriteButton(work: work),
        OutlinedButton.icon(
          style: hikoOutlinedPillStyle(isDark: isDark),
          onPressed: () => unawaited(_openInBrowser(work)),
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: Text('在浏览器打开', style: actionStyle),
        ),
        OutlinedButton.icon(
          style: hikoOutlinedPillStyle(isDark: isDark),
          onPressed: work.rjCode == null
              ? null
              : () => unawaited(_copyRj(work.rjCode!)),
          icon: const Icon(Icons.content_copy_rounded, size: 15),
          label: Text('复制 RJ 号', style: actionStyle),
        ),
        if (folderKeys.isNotEmpty)
          OutlinedButton.icon(
            style: hikoOutlinedPillStyle(isDark: isDark),
            onPressed: () => setState(() {
              if (allExpanded) {
                _expanded.clear();
              } else {
                _expanded
                  ..clear()
                  ..addAll(folderKeys);
              }
            }),
            icon: Icon(
              allExpanded
                  ? Icons.unfold_less_rounded
                  : Icons.unfold_more_rounded,
              size: 15,
            ),
            label: Text(
              allExpanded ? '折叠全部' : '展开全部',
              style: actionStyle,
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- 曲目树

  List<Widget> _buildTrackList({
    required OnlineDetail detail,
    required String? currentHash,
    required bool isCurrentWork,
    required bool isPlaying,
  }) {
    if (detail.audioTracks.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '服务器未返回可播放的音轨',
            style: TextStyle(
              fontSize: 12 * _textScale,
              color: Theme.of(context).hintColor,
            ),
          ),
        ),
      ];
    }
    final out = <Widget>[];
    if (detail.tree.isEmpty) {
      // 兜底：服务端没给层级时，按 relativePath 分组顺序编号
      _buildFlat(detail, currentHash, isCurrentWork, isPlaying, out);
    } else {
      _walkNodes(
        detail,
        detail.tree,
        depth: 0,
        parentPath: '',
        currentHash: currentHash,
        isCurrentWork: isCurrentWork,
        isPlaying: isPlaying,
        out: out,
      );
    }
    return out;
  }

  /// 递归渲染目录树，**不限深度**（裁决 Q3）。
  ///
  /// - 只渲染可播放音频，以及「子树里含有音频」的目录；仅存字幕/图片的目录整支隐去
  /// - 序号在**每一层内**独立计数，还原 asmr.one 的分组观感
  void _walkNodes(
    OnlineDetail detail,
    List<OnlineNode> nodes, {
    required int depth,
    required String parentPath,
    required String? currentHash,
    required bool isCurrentWork,
    required bool isPlaying,
    required List<Widget> out,
  }) {
    var seq = 0;
    for (final node in nodes) {
      if (node is OnlineFolderNode) {
        if (node.audioCount == 0) continue;
        final path =
            parentPath.isEmpty ? node.title : '$parentPath/${node.title}';
        final collapsed = !_expanded.contains(path);
        out.add(_FolderRow(
          title: node.title,
          audioCount: node.audioCount,
          totalSeconds: node.totalSeconds,
          depth: depth,
          collapsed: collapsed,
          onToggle: () => setState(() {
            // 与 1.91.0 同样的「先试着删，删不掉就加」写法，只是集合反了过来
            if (!_expanded.remove(path)) _expanded.add(path);
          }),
          onPlay: () => unawaited(
            _playFrom(detail: detail, queue: playableIn(node)),
          ),
        ));
        if (!collapsed) {
          _walkNodes(
            detail,
            node.children,
            depth: depth + 1,
            parentPath: path,
            currentHash: currentHash,
            isCurrentWork: isCurrentWork,
            isPlaying: isPlaying,
            out: out,
          );
        }
        continue;
      }
      if (node is OnlineFileNode) {
        final track = node.track;
        if (!track.playable) continue;
        seq++;
        out.add(_trackRow(
          detail,
          track,
          index: seq,
          depth: depth,
          currentHash: currentHash,
          isCurrentWork: isCurrentWork,
          isPlaying: isPlaying,
        ));
      }
    }
  }

  /// 无层级数据时的兜底：按 `relativePath` 顺序编号
  void _buildFlat(
    OnlineDetail detail,
    String? currentHash,
    bool isCurrentWork,
    bool isPlaying,
    List<Widget> out,
  ) {
    var seq = 0;
    var lastPath = '';
    for (final track in detail.audioTracks) {
      if (track.relativePath != lastPath) {
        lastPath = track.relativePath;
        seq = 0;
      }
      seq++;
      out.add(_trackRow(
        detail,
        track,
        index: seq,
        depth: 0,
        currentHash: currentHash,
        isCurrentWork: isCurrentWork,
        isPlaying: isPlaying,
      ));
    }
  }

  Widget _trackRow(
    OnlineDetail detail,
    OnlineTrack track, {
    required int index,
    required int depth,
    required String? currentHash,
    required bool isCurrentWork,
    required bool isPlaying,
  }) {
    final active = isCurrentWork && currentHash == track.hash;
    return HikoTrackRow(
      // 当前行挂全局 key，供「自动滚到正在播放的那一行」定位（裁决 Q2）。
      // 同一时刻只可能有一行 active，所以这个 key 不会撞。
      key: active ? _activeRowKey : null,
      index: index,
      name: onlineTrackDisplayName(track.title),
      durationSeconds: track.duration,
      active: active,
      playing: active && isPlaying,
      indent: depth * 14.0,
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

  // ---------------------------------------------------------------- 自动展开

  /// 裁决 Q2：正在播放的那一行必须看得见。
  ///
  /// 默认全折叠（Q9）之后这条从「锦上添花」变成必需品 —— 切歌切进别的目录时，
  /// 当前行会彻底隐形，用户根本不知道播的是哪一首。
  ///
  /// 只在**当前曲目 hash 变化**时动手（靠 `_revealedHash` 去重），因此：
  /// ① 同一首不会每帧重复触发；② 用户手动把它折回去后，下一帧不会被强行再打开。
  /// 展开只**增不减** —— 用户自己开过的目录不会被顺手关掉。
  void _maybeRevealPlaying({
    required OnlineDetail detail,
    required bool isCurrentWork,
    required String? hash,
  }) {
    if (!isCurrentWork || hash == null || _revealedHash == hash) return;
    // 歌词页时曲目行根本没构建，等用户切回曲目页再说：
    // 那次 setState 会重新走一遍 build，这里仍会被调用。
    if (_tabIndex != 0) return;
    // 先记账再调度：同一帧内 build 可能被调用多次，避免重复排回调
    _revealedHash = hash;

    final chain = pathToHash(detail.tree, hash);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (chain.isEmpty) {
        // 文件就躺在作品根下，本来就渲染了，当前帧即可滚动
        _scrollToActiveRow();
        return;
      }
      setState(() => _expanded.addAll(chain));
      // 展开要等下一帧 build + layout 才生效，届时目标行才有 RenderObject，
      // 所以滚动必须再挂一次 post-frame。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToActiveRow();
      });
    });
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
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      ),
    );
  }

  // ---------------------------------------------------------------- 交互

  /// 声优 / 社团胶囊的点击菜单（1.97.0）：按此筛选 / 复制名字。
  ///
  /// 菜单锚在胶囊自己的位置 —— `pillContext` 由外层 [Builder] 提供，
  /// 用本 State 的 context 会把菜单钉到整个面板左上角去。
  Future<void> _showCreatorMenu(
    BuildContext pillContext, {
    required String name,
    required OnlineCreatorKind kind,
  }) async {
    final box = pillContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(pillContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null || !pillContext.mounted) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final isVa = kind == OnlineCreatorKind.va;
    final action = await showMenu<String>(
      context: pillContext,
      position: position,
      constraints: const BoxConstraints(minWidth: 140),
      items: [
        PopupMenuItem(
          value: 'filter',
          height: 36,
          child: Text(
            isVa ? '按此声优筛选' : '按此社团筛选',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        PopupMenuItem(
          value: 'copy',
          height: 36,
          child: const Text('复制名字', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'filter':
        widget.onSelectCreator!(
          OnlineCreatorFilter(kind: kind, name: name),
        );
      case 'copy':
        await Clipboard.setData(ClipboardData(text: name));
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(SnackBar(content: Text('已复制 $name')));
        }
      default:
        break;
    }
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
    // 收藏按钮在详情面板里，跟着详情倍率走（不在面板里时作用域缺省为 1.0）
    final textScale = HikoDetailTextScale.of(context);

    if (!account.loggedIn) {
      return OutlinedButton.icon(
        style: hikoOutlinedPillStyle(isDark: isDark),
        // 恢复登录态期间禁用：否则冷启动那一下会闪出「去登录」，
        // 而用户其实早就登录了
        onPressed: account.settled
            ? () => unawaited(
                  showLoginRequiredDialog(context, action: '收藏作品'),
                )
            : null,
        icon: const Icon(Icons.bookmark_border_rounded, size: 15),
        label: Text('收藏', style: TextStyle(fontSize: 11 * textScale)),
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

    final button = OutlinedButton.icon(
      style: highlighted
          ? OutlinedButton.styleFrom(
              // 与 hikoOutlinedPillStyle 同一套几何（圆角 / 内边距），只换配色
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              side: BorderSide(
                color: hikoFavoriteColor.withValues(alpha: 0.5),
              ),
              backgroundColor: hikoFavoriteColor.withValues(
                alpha: isDark ? 0.16 : 0.08,
              ),
            )
          : hikoOutlinedPillStyle(isDark: isDark),
      onPressed: () => unawaited(showPlaylistPicker(context, work: work)),
      icon: Icon(
        highlighted
            ? Icons.bookmark_rounded
            : Icons.bookmark_border_rounded,
        size: 15,
        color: highlighted ? hikoFavoriteColor : null,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11 * textScale,
          fontWeight: highlighted ? FontWeight.w600 : null,
          color: highlighted ? hikoFavoriteColor : null,
        ),
      ),
    );
    if (names.isEmpty) return button;
    return Tooltip(message: '已在：${names.join('、')}', child: button);
  }
}

/// 目录行（裁决 Q14=C）：折叠三角 + 文件夹名 + 「N 个项目 · 总时长」，
/// hover 时右侧换成播放图标（播放该目录下的全部音频）。
class _FolderRow extends StatefulWidget {
  const _FolderRow({
    required this.title,
    required this.audioCount,
    required this.totalSeconds,
    required this.depth,
    required this.collapsed,
    required this.onToggle,
    required this.onPlay,
  });

  final String title;
  final int audioCount;
  final double totalSeconds;
  final int depth;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onPlay;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textScale = HikoDetailTextScale.of(context);

    return Padding(
      padding: EdgeInsets.only(left: widget.depth * 14.0),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onToggle,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: _hovered
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                AnimatedRotation(
                  // 0.25 圈 = 90°：展开时朝下，折叠时朝右
                  turns: widget.collapsed ? 0 : 0.25,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_right_rounded,
                    size: 16,
                    color: theme.hintColor,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.folder_rounded, size: 15, color: hikoRatingColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12 * textScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_hovered)
                  Tooltip(
                    message: '播放该目录',
                    child: InkWell(
                      onTap: widget.onPlay,
                      mouseCursor: SystemMouseCursors.click,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    '${widget.audioCount} 个项目 · '
                    '${formatDuration(widget.totalSeconds)}',
                    style: TextStyle(
                      fontSize: 10 * textScale,
                      color: theme.hintColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
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
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 30, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12 * HikoDetailTextScale.of(context),
                color: theme.hintColor,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
