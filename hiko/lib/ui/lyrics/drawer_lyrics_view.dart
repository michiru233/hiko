import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../lyrics/models/lyric_line.dart';
import '../../utils/time.dart';
import 'lyrics_auto_scroll.dart';
import '../m3e/m3e.dart';

/// 抽屉歌词视图组件（支持垂直平滑滚动、高亮当前句、悬停显示时间点、点击跳转、角色 Badge）
class DrawerLyricsView extends ConsumerStatefulWidget {
  const DrawerLyricsView({super.key});

  @override
  ConsumerState<DrawerLyricsView> createState() => _DrawerLyricsViewState();
}

class _DrawerLyricsViewState extends ConsumerState<DrawerLyricsView>
    with LyricsAutoScroll<DrawerLyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};

  @override
  ScrollController get lyricsScrollController => _scrollController;

  @override
  Map<int, GlobalKey> get lyricsLineKeys => _lineKeys;

  @override
  double get lyricsEstimatedLineHeight =>
      45.0 * ref.read(settingsProvider).lyricsFontScale;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsProvider);
    final theme = M3ETheme.of(context);
    final colors = theme.colors;

    // 监听高亮行变化并在允许自动滚动时触发丝滑平移
    if (lyricsState.autoScrollEnabled &&
        lyricsState.activeIndex != lastRevealedIndex &&
        lyricsState.activeIndex >= 0) {
      lastRevealedIndex = lyricsState.activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          revealLyricsLine(lyricsState.activeIndex);
        }
      });
    }

    if (lyricsState.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: M3ELoadingIndicator(size: 24)),
      );
    }

    if (!lyricsState.hasLyrics) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subtitles_off_outlined,
                size: 40,
                color: colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                '暂未检测到同名歌词/字幕',
                style: theme.type.titleSmall.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '将 .lrc 或 .vtt 文件放入音频同级目录\n或 lyrics/、subtitles/ 子目录即可自动同步',
                textAlign: TextAlign.center,
                style: theme.type.bodySmall.copyWith(
                  height: 1.4,
                  color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lines = lyricsState.lines;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          ref.read(lyricsProvider.notifier).userScrolled();
        }
        return false;
      },
      child: Stack(
        children: [
          // 上下各留半个可视高度，首句与末句才能也滚到正中
          LayoutBuilder(
            builder: (context, constraints) => ListView.separated(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: lyricsCenterSlack(constraints.maxHeight),
              ),
              itemCount: lines.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final line = lines[index];
                final isActive = index == lyricsState.activeIndex;
                final key = _lineKeys.putIfAbsent(index, () => GlobalKey());

                return _LyricLineWidget(
                  key: key,
                  line: line,
                  isActive: isActive,
                  onTap: () {
                    ref.read(lyricsProvider.notifier).seekToLine(index);
                  },
                );
              },
            ),
          ),
          // 若用户手动滑动中断了自动跟随，显示浮动恢复按钮
          if (!lyricsState.autoScrollEnabled && lyricsState.activeIndex >= 0)
            Positioned(
              right: 16,
              bottom: 16,
              child: M3EFab(
                size: 40,
                radius: M3EShape.lg,
                semanticLabel: '回到当前播放行',
                onPressed: () {
                  ref.read(lyricsProvider.notifier).resumeAutoScroll();
                  revealLyricsLine(lyricsState.activeIndex);
                },
                child: const Icon(Icons.vertical_align_center_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class _LyricLineWidget extends StatefulWidget {
  final LyricLine line;
  final bool isActive;
  final VoidCallback onTap;

  const _LyricLineWidget({
    super.key,
    required this.line,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_LyricLineWidget> createState() => _LyricLineWidgetState();
}

class _LyricLineWidgetState extends State<_LyricLineWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;

    // 1.99.46：行高/字号仍是承重 metrics（45 × lyricsFontScale 的估算行高），
    // 只把颜色与状态层换成 M3E 语义色；发光指示条已删除（审计 C-05）。
    final textColor = widget.isActive
        ? colors.onSurface
        : colors.onSurfaceVariant;
    final fontWeight = widget.isActive ? FontWeight.w700 : FontWeight.w500;
    final fontSize = widget.isActive ? 15.5 : 13.5;

    final radius = BorderRadius.circular(M3EShape.sm);
    return M3EPressable(
      onTap: widget.onTap,
      borderRadius: radius,
      pressScale: 0.99,
      onHoverChanged: (hovered) => setState(() => _isHovered = hovered),
      child: AnimatedContainer(
        duration: theme.motion.stateLayerDuration,
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: widget.isActive
              ? colors.secondaryContainer
              : Colors.transparent,
          borderRadius: radius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 活跃指示条 / 悬停播放小图标（无发光）
            SizedBox(
              width: 18,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: widget.isActive
                    ? Container(
                        width: 4,
                        height: 16,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      )
                    : (_isHovered
                          ? Icon(
                              Icons.play_arrow_rounded,
                              size: 14,
                              color: colors.primary.withValues(alpha: 0.8),
                            )
                          : const SizedBox(width: 4)),
              ),
            ),
            const SizedBox(width: 4),

            // 歌词正文 & 角色 Badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (widget.line.speaker != null &&
                      widget.line.speaker!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: widget.isActive
                              ? colors.secondaryContainer
                              : colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(M3EShape.xs),
                        ),
                        child: Text(
                          widget.line.speaker!,
                          style: theme.type.labelSmall.copyWith(
                            color: widget.isActive
                                ? colors.onSecondaryContainer
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  Text(
                    widget.line.text,
                    style: theme.type.bodyMedium.copyWith(
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                      height: 1.45,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),

            // 右侧时间点（悬停或活跃时展示）
            if (_isHovered || widget.isActive)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 2),
                child: Text(
                  formatTime(widget.line.startTime.inMilliseconds / 1000.0),
                  style: theme.type.labelSmall.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: widget.isActive
                        ? colors.primary
                        : colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
