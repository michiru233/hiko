import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/online/kikoeru_client.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../playback/playback_controller.dart';
import '../../utils/time.dart';
import '../lyrics/drawer_lyrics_view.dart';
import '../theme.dart';
import '../transitions/fullscreen_player_route.dart';
import 'detail_kit.dart';
import 'online_cover.dart';

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
    this.onSelectTagName,
  });

  final int workId;
  final VoidCallback onClose;
  final void Function(String tagName)? onSelectTagName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // 氛围背板的底图：整块被 σ55 糊掉，只留色块，不构成隐私风险
    final coverUrl = ref.watch(onlineClientProvider).coverUrl(workId);

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
              onSelectTagName: onSelectTagName,
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
  const OnlineDetailScreen({super.key, required this.workId, this.onSelectTagName});

  final int workId;
  final void Function(String tagName)? onSelectTagName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作品详情', style: TextStyle(fontSize: 15)),
      ),
      body: OnlineDetailBody(
        key: ValueKey<int>(workId),
        workId: workId,
        onSelectTagName: onSelectTagName,
      ),
    );
  }
}

/// 详情主体：面板与全屏页共用。
///
/// 结构骨架对齐本地 `DetailDrawer`（裁决 Q8=B）：封面 → 眼眉胶囊 → 标题 →
/// 声优/社团行 → 胶囊 → 操作行 → 信息行 → 标签 → 双 Tab → 曲目树/歌词。
class OnlineDetailBody extends ConsumerStatefulWidget {
  const OnlineDetailBody({super.key, required this.workId, this.onSelectTagName});

  final int workId;
  final void Function(String tagName)? onSelectTagName;

  @override
  ConsumerState<OnlineDetailBody> createState() => _OnlineDetailBodyState();
}

class _OnlineDetailBodyState extends ConsumerState<OnlineDetailBody> {
  /// 0: 曲目列表, 1: 歌词字幕（裁决 Q12=A）
  int _tabIndex = 0;

  /// 已折叠的目录路径键。默认空集 = 全展开（裁决 Q4=A，忠实呈现服务器内容）
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    return ref.watch(onlineDetailProvider(widget.workId)).when(
          loading: () => const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (error, _) => _ErrorView(
            message: '$error',
            onRetry: () => ref.invalidate(onlineDetailProvider(widget.workId)),
          ),
          data: (detail) => _buildContent(context, detail),
        );
  }

  // ---------------------------------------------------------------- 主体

  Widget _buildContent(BuildContext context, OnlineDetail detail) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final work = detail.work;
    final audio = detail.audioTracks;
    final client = ref.watch(onlineClientProvider);

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
    final allCollapsed =
        folderKeys.isNotEmpty && _collapsed.length >= folderKeys.length;

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
                  child: OnlineCover(url: client.coverUrl(work.id)),
                ),
              ),
            ),
            const SizedBox(height: 22),
            // 眼眉胶囊：来源 · RJ 号（裁决 Q9=A，纯标识不可点）
            HikoEyebrowPill(label: '在线 · ${work.rjCode ?? '#${work.id}'}'),
            const SizedBox(height: 10),
            Text(
              work.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle(work),
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            // 社团（紫）/ 声优（蓝）胶囊：在线数据是只读的，纯展示不可点（裁决 Q9=A）
            if (work.circleName.isNotEmpty || work.vas.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (work.circleName.isNotEmpty)
                    HikoPersonPill(name: work.circleName, color: hikoCircleColor),
                  for (final name in work.vas)
                    HikoPersonPill(name: name, color: hikoVoiceColor),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _buildActions(context, detail, folderKeys, allCollapsed),
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
                      tag: t,
                      // 详情接口只给标签名不给 id，点选后由外层在标签表里反查 id
                      onTap: widget.onSelectTagName == null
                          ? null
                          : () => widget.onSelectTagName!(t),
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
    bool allCollapsed,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final work = detail.work;
    final audio = detail.audioTracks;

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
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton.icon(
          style: hikoOutlinedPillStyle(isDark: isDark),
          onPressed: () => unawaited(_openInBrowser(work)),
          icon: const Icon(Icons.open_in_new_rounded, size: 15),
          label: const Text('在浏览器打开', style: TextStyle(fontSize: 11)),
        ),
        OutlinedButton.icon(
          style: hikoOutlinedPillStyle(isDark: isDark),
          onPressed: work.rjCode == null
              ? null
              : () => unawaited(_copyRj(work.rjCode!)),
          icon: const Icon(Icons.content_copy_rounded, size: 15),
          label: const Text('复制 RJ 号', style: TextStyle(fontSize: 11)),
        ),
        if (folderKeys.isNotEmpty)
          OutlinedButton.icon(
            style: hikoOutlinedPillStyle(isDark: isDark),
            onPressed: () => setState(() {
              if (allCollapsed) {
                _collapsed.clear();
              } else {
                _collapsed
                  ..clear()
                  ..addAll(folderKeys);
              }
            }),
            icon: Icon(
              allCollapsed
                  ? Icons.unfold_more_rounded
                  : Icons.unfold_less_rounded,
              size: 15,
            ),
            label: Text(
              allCollapsed ? '展开全部' : '折叠全部',
              style: const TextStyle(fontSize: 11),
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
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
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
        final collapsed = _collapsed.contains(path);
        out.add(_FolderRow(
          title: node.title,
          audioCount: node.audioCount,
          totalSeconds: node.totalSeconds,
          depth: depth,
          collapsed: collapsed,
          onToggle: () => setState(() {
            if (!_collapsed.remove(path)) _collapsed.add(path);
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
      index: index,
      name: onlineTrackDisplayName(track.title),
      durationSeconds: track.duration,
      active: active,
      playing: active && isPlaying,
      indent: depth * 14.0,
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

  // ---------------------------------------------------------------- 交互

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
                    style: const TextStyle(
                      fontSize: 12,
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
                      fontSize: 10,
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
