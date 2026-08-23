import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lyrics/lyrics_controller.dart';
import '../../lyrics/models/lyric_line.dart';
import '../../utils/time.dart';

/// 抽屉歌词视图组件（支持垂直平滑滚动、高亮当前句、悬停显示时间点、点击跳转、角色 Badge）
class DrawerLyricsView extends ConsumerStatefulWidget {
  const DrawerLyricsView({super.key});

  @override
  ConsumerState<DrawerLyricsView> createState() => _DrawerLyricsViewState();
}

class _DrawerLyricsViewState extends ConsumerState<DrawerLyricsView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLine(int index) {
    if (index < 0) return;
    final key = _lineKeys[index];
    if (key == null || key.currentContext == null) return;

    final context = key.currentContext!;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
      alignment: 0.35, // 滚动至可视区域上方 35% 黄金视线处
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyricsState = ref.watch(lyricsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 监听高亮行变化并在允许自动滚动时触发丝滑平移
    if (lyricsState.autoScrollEnabled &&
        lyricsState.activeIndex != _lastActiveIndex &&
        lyricsState.activeIndex >= 0) {
      _lastActiveIndex = lyricsState.activeIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToActiveLine(lyricsState.activeIndex);
        }
      });
    }

    if (lyricsState.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
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
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(height: 12),
              Text(
                '暂未检测到同名歌词/字幕',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '将 .lrc 或 .vtt 文件放入音频同级目录\n或 lyrics/、subtitles/ 子目录即可自动同步',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: isDark ? Colors.white30 : Colors.black26,
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
          ListView.separated(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            itemCount: lines.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
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
          // 若用户手动滑动中断了自动跟随，显示浮动恢复按钮
          if (!lyricsState.autoScrollEnabled && lyricsState.activeIndex >= 0)
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.small(
                onPressed: () {
                  ref.read(lyricsProvider.notifier).resumeAutoScroll();
                  _scrollToActiveLine(lyricsState.activeIndex);
                },
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                elevation: 3,
                tooltip: '回到当前播放行',
                child: const Icon(Icons.vertical_align_center_rounded, size: 18),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final textColor = widget.isActive
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? Colors.white.withValues(alpha: 0.45) : Colors.black45);

    final fontWeight = widget.isActive ? FontWeight.w700 : FontWeight.w500;
    final fontSize = widget.isActive ? 15.5 : 13.5;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: widget.isActive
                  ? primaryColor.withValues(alpha: isDark ? 0.16 : 0.08)
                  : (_isHovered
                      ? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03))
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: widget.isActive
                  ? Border.all(
                      color: primaryColor.withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 活跃呼吸微光指示条 / 悬停播放小图标
                Container(
                  width: 18,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.only(top: 2),
                  child: widget.isActive
                      ? Container(
                          width: 4,
                          height: 16,
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.6),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        )
                      : (_isHovered
                          ? Icon(
                              Icons.play_arrow_rounded,
                              size: 14,
                              color: primaryColor.withValues(alpha: 0.8),
                            )
                          : const SizedBox(width: 4)),
                ),
                const SizedBox(width: 4),

                // 歌词正文 & 角色 Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.line.speaker != null && widget.line.speaker!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: primaryColor.withValues(alpha: widget.isActive ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.line.speaker!,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: primaryColor,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        widget.line.text,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: fontWeight,
                          height: 1.45,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // 右侧时间点指示（悬停或活跃时展示）
                if (_isHovered || widget.isActive)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 2),
                    child: Text(
                      formatTime(widget.line.startTime.inMilliseconds / 1000.0),
                      style: TextStyle(
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: widget.isActive ? primaryColor : (isDark ? Colors.white38 : Colors.black38),
                      ),
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
