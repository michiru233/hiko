import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../models/album.dart';
import '../../playback/gain_chain.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_rules.dart';
import '../../playback/sleep_timer.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../lyrics/lyrics_auto_scroll.dart';
import '../theme.dart';
import '../widgets/toast.dart';

/// 全屏播放页（1.57）：仿网易云双层设计
/// - 黑胶唱片层：封面旋转动画 + 唱针抬起/落下拟真联动
/// - 歌词层：滚动字幕同步播放进度
/// - 三核心功能键：睡眠定时、音频增益、音轨/章节列表/详情信息
class FullscreenPlayerScreen extends ConsumerStatefulWidget {
  const FullscreenPlayerScreen({super.key});

  @override
  ConsumerState<FullscreenPlayerScreen> createState() =>
      _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends ConsumerState<FullscreenPlayerScreen>
    with
        SingleTickerProviderStateMixin,
        LyricsAutoScroll<FullscreenPlayerScreen> {
  late AnimationController _rotationController;
  final ScrollController _lyricsScrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  bool _showLyrics = false;
  bool _dragging = false;
  double _dragValue = 0;

  @override
  ScrollController get lyricsScrollController => _lyricsScrollController;

  @override
  Map<int, GlobalKey> get lyricsLineKeys => _lineKeys;

  @override
  double get lyricsEstimatedLineHeight =>
      45.0 * ref.read(settingsProvider).lyricsFontScale;

  @override
  void initState() {
    super.initState();
    // 黑胶旋转动画：持续旋转，播放时运行，暂停时停止
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final album = state.album;
    final track = state.currentTrack;

    // 尊重系统 reduce-motion 设置，禁用动画时停止旋转
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // 同步旋转动画与播放状态
    if (!reduceMotion && state.playing && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (reduceMotion ||
        (!state.playing && _rotationController.isAnimating)) {
      _rotationController.stop();
    }

    if (album == null) {
      // 无播放内容时关闭页面
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final position = _dragging ? _dragValue : state.position;
    final duration = state.duration;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? HikoColors.darkBg : HikoColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.keyboard_arrow_down,
              color: isDark ? Colors.white : Colors.black87,
              size: 24,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // 歌词/封面切换按钮
          IconButton(
            icon: Icon(
              _showLyrics ? Icons.album : Icons.lyrics,
              color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
            ),
            onPressed: () => _setShowLyrics(!_showLyrics),
            tooltip: _showLyrics ? '显示封面' : '显示歌词',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // 中央区域：黑胶唱片层或歌词层，切换带 220ms 交叉淡入淡出
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _showLyrics
                    ? KeyedSubtree(
                        key: const ValueKey('lyrics'),
                        child: _buildLyricsView(theme, isDark),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('vinyl'),
                        child: _buildVinylView(
                          album,
                          theme,
                          isDark,
                          state.playing,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            // 曲目信息
            _buildTrackInfo(album, track, theme, isDark),
            const SizedBox(height: 12),
            // 进度条
            _buildProgressBar(position, duration, theme, isDark),
            const SizedBox(height: 12),
            // 播放控制
            _buildPlaybackControls(state, theme, isDark),
            const SizedBox(height: 8),
            // 三核心功能键
            _buildFunctionButtons(state, settings, theme, isDark),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 切换中央区域显示（黑胶唱片层 / 歌词层）。
  ///
  /// 三个入口共用：点中央区域、点歌词页留白、AppBar 图标按钮。
  /// 进入歌词页时重置滚动记账并恢复自动跟随——歌词列表在切到唱片层时整棵被销毁，
  /// 重进必然从 offset 0 重建，不重新定位就会看到歌曲开头而不是当前唱到的那句。
  void _setShowLyrics(bool show) {
    if (show == _showLyrics) return;
    HapticFeedback.selectionClick();
    if (show) {
      ref.read(lyricsProvider.notifier).resumeAutoScroll();
    }
    setState(() {
      _showLyrics = show;
      if (show) lastRevealedIndex = -1;
    });
  }

  /// 黑胶唱片视图：封面旋转 + 唱针联动
  Widget _buildVinylView(
    Album album,
    ThemeData theme,
    bool isDark,
    bool isPlaying,
  ) {
    return GestureDetector(
      // 铺满整个中央区域：唱片圆盘之外还有上下各约 50px，点到那里也该有反应
      behavior: HitTestBehavior.opaque,
      onTap: () => _setShowLyrics(true),
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // 旋转的黑胶唱片外圈 - 使用 RepaintBoundary 隔离重绘
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _rotationController.value * 2 * math.pi,
                    child: child,
                  );
                },
                // 静态黑胶唱片作为 child，不重复构建
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // 黑胶唱片外圈：黑色圆环
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFF1a1a1a),
                        Color(0xFF0d0d0d),
                        Colors.black,
                      ],
                      stops: [0.7, 0.85, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 40,
                        offset: const Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Center(
                    // 封面图片（占中间部分）
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: AlbumCover(album: album, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 中心圆孔（在封面上）
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF0d0d0d)
                    : const Color(0xFF2a2a2a),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.2),
                  width: 2,
                ),
              ),
            ),
            // 唱针（右上角）：改为更真实的唱针臂设计
            Positioned(
              top: -30,
              right: 40,
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 400),
                turns: isPlaying ? 0.08 : -0.08, // 播放时落下，暂停时抬起
                alignment: const Alignment(0.3, -0.8), // 旋转中心靠近唱针臂顶部
                child: CustomPaint(
                  size: const Size(100, 140),
                  painter: _VinylArmPainter(isDark: isDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 歌词视图（带自动滚动）
  Widget _buildLyricsView(ThemeData theme, bool isDark) {
    final lyrics = ref.watch(lyricsProvider);
    final settings = ref.watch(settingsProvider);

    if (!lyrics.hasLyrics) {
      // 无歌词时整个中央区可点回唱片层，与有歌词时的留白手势同语义
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _setShowLyrics(false),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '暂无歌词',
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '点击返回唱片',
                style: TextStyle(
                  fontSize: 12,
                  color: (isDark
                          ? HikoColors.darkMuted
                          : HikoColors.lightMuted)
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final lines = lyrics.lines;
    final currentIndex = lyrics.activeIndex;
    final lyricsFontScale = settings.lyricsFontScale;

    // 自动滚动到当前行
    if (currentIndex >= 0 &&
        currentIndex != lastRevealedIndex &&
        lyrics.autoScrollEnabled) {
      lastRevealedIndex = currentIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        revealLyricsLine(currentIndex);
      });
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          // 用户手动滚动时暂停自动跟随
          ref.read(lyricsProvider.notifier).userScrolled();
        }
        return true;
      },
      child: Stack(
        children: [
          // 上下各留半个可视高度，首句与末句才能也滚到正中
          // 外层手势只包 ListView（不包整个 Stack），右下角浮层按钮才吃得到自己的点击
          LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              // 点歌词区的留白（首句之上／末句之下）回到唱片层
              behavior: HitTestBehavior.opaque,
              onTap: () => _setShowLyrics(false),
              child: ListView.builder(
                controller: _lyricsScrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: lyricsCenterSlack(constraints.maxHeight),
                ),
                itemCount: lines.length,
                itemBuilder: (context, index) {
                  final isCurrent = index == currentIndex;
                  final line = lines[index];
                  return GestureDetector(
                    // 故意吸收点击，不是死代码：点在某句歌词文字上不该落进外层的
                    // 翻页手势里，只有真正的空白处才切回唱片层。
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: Padding(
                      key: _lineKeys.putIfAbsent(index, () => GlobalKey()),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: (isCurrent ? 18 : 15) * lyricsFontScale,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isCurrent
                              ? (isDark
                                    ? HikoColors.darkInk
                                    : HikoColors.lightInk)
                              : (isDark
                                    ? HikoColors.darkMuted
                                    : HikoColors.lightMuted),
                          height: 1.8,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 右下角浮层按钮：手动滑走后给「回到当前句」，下方常驻歌词字号
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!lyrics.autoScrollEnabled && currentIndex >= 0) ...[
                  _buildLyricsOverlayButton(
                    icon: Icons.vertical_align_center_rounded,
                    tooltip: '回到当前句',
                    isDark: isDark,
                    onPressed: () {
                      ref.read(lyricsProvider.notifier).resumeAutoScroll();
                      revealLyricsLine(currentIndex);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                _buildLyricsOverlayButton(
                  icon: Icons.text_fields,
                  tooltip: '调整歌词字号',
                  isDark: isDark,
                  onPressed: () =>
                      _showLyricsFontScaleDialog(settings, theme, isDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 曲目信息（减小字号）
  Widget _buildTrackInfo(
    Album album,
    dynamic track,
    ThemeData theme,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            track?.name ?? album.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            album.artist,
            style: TextStyle(
              fontSize: 15,
              color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// 歌词层右下角的浮层胶囊按钮（半透明底，压在歌词之上）
  Widget _buildLyricsOverlayButton({
    required IconData icon,
    required String tooltip,
    required bool isDark,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
          size: 20,
        ),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  /// 进度条
  Widget _buildProgressBar(
    double position,
    double duration,
    ThemeData theme,
    bool isDark,
  ) {
    // 拖动时显示拖动位置，否则显示实际播放位置
    final displayPosition = _dragging ? _dragValue : position;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.1),
              thumbColor: theme.colorScheme.primary,
              overlayColor: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: duration > 0 ? displayPosition.clamp(0, duration) : 0,
              max: duration > 0 ? duration : 1,
              onChanged: (v) => setState(() {
                _dragging = true;
                _dragValue = v;
              }),
              onChangeEnd: (v) {
                ref.read(playbackProvider.notifier).seek(v);
                setState(() => _dragging = false);
                // 拖进度条就是「我要跳到那一刻」：落地即恢复跟随并强制重新居中。
                // 若用户在拖动前手动滑走过歌词，自动跟随正处在暂停窗口里，
                // 不重置这份记账的话歌词会停在原处，要等下一句变化才自愈。
                ref.read(lyricsProvider.notifier).resumeAutoScroll();
                lastRevealedIndex = -1;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatTime(displayPosition),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? HikoColors.darkMuted
                        : HikoColors.lightMuted,
                  ),
                ),
                Text(
                  formatTime(duration),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? HikoColors.darkMuted
                        : HikoColors.lightMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 播放控制
  Widget _buildPlaybackControls(dynamic state, ThemeData theme, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一曲
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 36),
          color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(playbackProvider.notifier).prev();
          },
        ),
        const SizedBox(width: 20),
        // 播放/暂停
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(
              state.playing ? Icons.pause : Icons.play_arrow,
              size: 32,
            ),
            color: theme.colorScheme.onPrimary,
            onPressed: () {
              HapticFeedback.mediumImpact(); // 主按钮使用更强烈的反馈
              ref.read(playbackProvider.notifier).toggle();
            },
          ),
        ),
        const SizedBox(width: 20),
        // 下一曲
        IconButton(
          icon: const Icon(Icons.skip_next, size: 36),
          color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(playbackProvider.notifier).next();
          },
        ),
      ],
    );
  }

  /// 四核心功能键：睡眠定时、音频增益、播放模式、音轨列表
  Widget _buildFunctionButtons(
    dynamic state,
    AppSettings settings,
    ThemeData theme,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 睡眠定时
          _buildFunctionButton(
            icon: Icons.bedtime_outlined,
            label: '定时',
            theme: theme,
            isDark: isDark,
            onTap: () => _showSleepTimerDialog(theme, isDark),
          ),
          // 音频增益
          _buildFunctionButton(
            icon: Icons.volume_up_outlined,
            label: '增益',
            theme: theme,
            isDark: isDark,
            onTap: () => _showGainDialog(settings, theme, isDark),
          ),
          // 播放模式
          _buildPlayModeButton(state.mode, theme, isDark),
          // 音轨列表
          _buildFunctionButton(
            icon: Icons.queue_music_outlined,
            label: '列表',
            theme: theme,
            isDark: isDark,
            onTap: () => _showTrackListSheet(state.album, state.queueIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionButton({
    required IconData icon,
    required String label,
    required ThemeData theme,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    // 扩大触摸目标到 56×56px（图标 28 + padding 14×2）
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact(); // 触觉反馈
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 28,
              color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 播放模式按钮（带菜单）
  Widget _buildPlayModeButton(
    PlaybackMode currentMode,
    ThemeData theme,
    bool isDark,
  ) {
    // 根据当前模式选择图标和标签
    final modeInfo = playModes.firstWhere((m) => m.key == currentMode.key);
    final IconData icon;
    switch (currentMode) {
      case PlaybackMode.list:
        icon = Icons.repeat_outlined;
        break;
      case PlaybackMode.single:
        icon = Icons.repeat_one_outlined;
        break;
      case PlaybackMode.shuffle:
        icon = Icons.shuffle_outlined;
        break;
      case PlaybackMode.album:
        icon = Icons.album; // 无 outlined 变体
        break;
    }

    return MenuAnchor(
      builder: (context, controller, child) {
        return InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 28,
                  color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                ),
                const SizedBox(height: 4),
                Text(
                  modeInfo.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? HikoColors.darkMuted
                        : HikoColors.lightMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      menuChildren: [
        // 菜单标题
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '播放模式',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 1),
        // 四种播放模式选项
        for (final mode in PlaybackMode.values)
          _buildPlayModeMenuItem(mode, currentMode, theme),
      ],
    );
  }

  /// 单个播放模式菜单项
  Widget _buildPlayModeMenuItem(
    PlaybackMode mode,
    PlaybackMode currentMode,
    ThemeData theme,
  ) {
    final info = playModes.firstWhere((m) => m.key == mode.key);
    final isSelected = mode == currentMode;

    // 图标
    final IconData leadingIcon;
    switch (mode) {
      case PlaybackMode.list:
        leadingIcon = Icons.repeat_outlined;
        break;
      case PlaybackMode.single:
        leadingIcon = Icons.repeat_one_outlined;
        break;
      case PlaybackMode.shuffle:
        leadingIcon = Icons.shuffle_outlined;
        break;
      case PlaybackMode.album:
        leadingIcon = Icons.album;
        break;
    }

    return MenuItemButton(
      leadingIcon: Icon(leadingIcon, size: 20),
      trailingIcon: isSelected ? const Icon(Icons.check, size: 20) : null,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(
          isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        ),
      ),
      onPressed: () async {
        HapticFeedback.selectionClick();
        await ref.read(playbackProvider.notifier).setMode(mode);
        await ref.read(settingsProvider.notifier).setPlayMode(mode.key);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            info.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            info.desc,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 歌词字号调节对话框
  Future<void> _showLyricsFontScaleDialog(
    AppSettings settings,
    ThemeData theme,
    bool isDark,
  ) async {
    final scales = [
      (0.85, '小'),
      (1.0, '标准'),
      (1.15, '大'),
      (1.30, '超大'),
      (1.50, '巨大'),
    ];

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('歌词字号', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (scale, label) in scales)
              RadioListTile<double>(
                title: Text(label),
                value: scale,
                groupValue: settings.lyricsFontScale,
                onChanged: (value) {
                  if (value != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setLyricsFontScale(value);
                    Navigator.pop(context);
                    showHikoToast(context, '歌词字号已设为 $label');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 睡眠定时对话框
  Future<void> _showSleepTimerDialog(ThemeData theme, bool isDark) async {
    final options = [5, 10, 15, 30, 45, 60];
    final state = ref.read(playbackProvider);
    final sleepMode = state.sleepMode;
    final sleepRemaining = state.sleepRemaining;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('睡眠定时', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sleepMode == SleepTimerMode.timed && sleepRemaining != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '剩余 ${(sleepRemaining.inMinutes + 1)} 分钟',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final min in options)
                  ElevatedButton(
                    onPressed: () {
                      ref.read(playbackProvider.notifier).setSleepMinutes(min);
                      Navigator.pop(context);
                      showHikoToast(context, '已设置 $min 分钟后停止播放');
                    },
                    child: Text('$min 分钟'),
                  ),
              ],
            ),
            if (sleepMode != SleepTimerMode.off) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  ref.read(playbackProvider.notifier).setSleepOff();
                  Navigator.pop(context);
                  showHikoToast(context, '已取消定时');
                },
                child: const Text('取消定时'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 音频增益对话框
  Future<void> _showGainDialog(
    AppSettings settings,
    ThemeData theme,
    bool isDark,
  ) async {
    double tempGain = settings.audioGain;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('音频增益', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'x${tempGain.toStringAsFixed(1)}',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Slider(
                value: tempGain,
                min: 1.0,
                max: desktopGainCap(),
                divisions: desktopGainCap() > 1.3 ? 30 : 3,
                label: 'x${tempGain.toStringAsFixed(1)}',
                onChanged: (v) {
                  setDialogState(() => tempGain = v);
                },
              ),
              Text(
                '调节后立即生效，范围 1.0x ~ ${desktopGainCap().toStringAsFixed(1)}x',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                ref.read(settingsProvider.notifier).setAudioGain(tempGain);
                ref.read(playbackProvider.notifier).setAudioGain(tempGain);
                Navigator.pop(context);
                showHikoToast(context, '增益已设为 x${tempGain.toStringAsFixed(1)}');
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 音轨列表底部弹窗
  Future<void> _showTrackListSheet(Album? album, int currentIndex) async {
    if (album == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDark ? HikoColors.darkCard : HikoColors.lightCard,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Text(
                          '播放列表',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? HikoColors.darkInk
                                : HikoColors.lightInk,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '共 ${album.tracks.length} 首',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? HikoColors.darkMuted
                                : HikoColors.lightMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: album.tracks.length,
                      // 优化滚动性能
                      cacheExtent: 500,
                      addAutomaticKeepAlives: true,
                      addRepaintBoundaries: true,
                      itemBuilder: (context, index) {
                        final track = album.tracks[index];
                        final isCurrent = index == currentIndex;
                        return Material(
                          color: isCurrent
                              ? theme.colorScheme.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          child: ListTile(
                            dense: true,
                            leading: SizedBox(
                              width: 32,
                              child: isCurrent
                                  ? Icon(
                                      Icons.volume_up,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    )
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? HikoColors.darkMuted
                                            : HikoColors.lightMuted,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                            title: Text(
                              track.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isCurrent
                                    ? theme.colorScheme.primary
                                    : (isDark
                                          ? HikoColors.darkInk
                                          : HikoColors.lightInk),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              formatTime(track.duration),
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? HikoColors.darkMuted
                                    : HikoColors.lightMuted,
                              ),
                            ),
                            onTap: () {
                              ref
                                  .read(playbackProvider.notifier)
                                  .playAlbum(album, index: index);
                              Navigator.pop(context);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 唱针臂绘制器：绘制真实的唱针形状
class _VinylArmPainter extends CustomPainter {
  final bool isDark;

  _VinylArmPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    // 唱针臂主体
    final armPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? [const Color(0xFF9e9e9e), const Color(0xFF616161)]
            : [const Color(0xFFbdbdbd), const Color(0xFF757575)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    // 唱针臂路径（细长的臂状）
    final armPath = Path()
      ..moveTo(size.width * 0.5, 0) // 顶部中心
      ..lineTo(size.width * 0.65, size.height * 0.6) // 右侧向下延伸
      ..lineTo(size.width * 0.55, size.height * 0.65) // 底部略窄
      ..lineTo(size.width * 0.35, size.height * 0.65)
      ..lineTo(size.width * 0.25, size.height * 0.6)
      ..close();

    canvas.drawPath(armPath, armPaint);

    // 唱针头部（小圆点）
    final needlePaint = Paint()
      ..color = isDark ? const Color(0xFF424242) : const Color(0xFF616161)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.45, size.height * 0.7),
      6,
      needlePaint,
    );

    // 唱针顶部圆形固定点
    final pivotPaint = Paint()
      ..color = isDark ? const Color(0xFF757575) : const Color(0xFF9e9e9e)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.5, 8), 8, pivotPaint);

    // 阴影
    final shadowPath = armPath.shift(const Offset(3, 3));
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawPath(shadowPath, shadowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
