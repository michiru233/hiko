import 'dart:async' show unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_account.dart';
import '../../data/online/online_favorites.dart';
import '../../data/online/online_models.dart';
import '../../data/settings_store.dart';
import '../../lyrics/desktop_lyrics_service.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../models/album.dart';
import '../../playback/gain_chain.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_rules.dart';
import '../../playback/sleep_timer.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../covers/cover_color.dart';
import '../detail_jump_requests.dart';
import '../lyrics/lyrics_auto_scroll.dart';
import '../m3e/m3e.dart';
import '../widgets/online_account_dialogs.dart';
import '../widgets/toast.dart';

/// 桌面歌词开关类 toast 的停留时长：比常规 toast 短，因为这几条全是
/// 「刚点的那一下已经给了反馈」的复述（非动效）。
const Duration kDesktopLyricsToastLinger = Duration(seconds: 1);

/// 播放页封面的明度呼吸周期（氛围动效，不是状态过渡，
/// 所以不进 `M3EMotion` 的三档弹簧）。
const Duration kBackdropBreathDuration = Duration(seconds: 6);


/// 全屏播放页（1.57 引入；1.99.29 M3E 重做，plan §8.5）。
///
/// - 黑胶拟物样式已移除（裁决 D7）：统一为大封面（320dp、角 28），
///   播放/暂停时角在 28↔32 间形变 + scale 1.0↔0.98（圆角插值 + 缩放近似，§7.4-2）
/// - 背景 = 封面主色的纵向三停渐变（不是模糊），播放中做 ±2% 明度呼吸
/// - Hero：入口带 [heroTag] 时封面参与路由转场形变（英雄时刻 A，§8.5）
/// - 控制区：M3EFab.large 主键 + M3ESlider 粗轨道进度
/// - 辅助区：M3EToolbar 全圆浮动工具条（含桌面端音量与悬浮歌词入口）
class FullscreenPlayerScreen extends ConsumerStatefulWidget {
  const FullscreenPlayerScreen({super.key, this.heroTag});

  /// 封面 Hero 目标 tag。由打开方传入（详情页封面 / 播放条封面各用不同 tag，
  /// 避免与首页卡片封面同 tag 撞「同路由多 Hero」断言）；null = 不参与 Hero。
  final String? heroTag;

  @override
  ConsumerState<FullscreenPlayerScreen> createState() =>
      _FullscreenPlayerScreenState();
}

class _FullscreenPlayerScreenState extends ConsumerState<FullscreenPlayerScreen>
    with
        SingleTickerProviderStateMixin,
        LyricsAutoScroll<FullscreenPlayerScreen> {
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
  void dispose() {
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

    if (album == null) {
      // 无播放内容时关闭页面
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final position = _dragging ? _dragValue : state.position;
    final duration = state.duration;

    // 1.83 宽屏并排：窗口 ≥1000px 时左封面右歌词同屏（封面区含曲目信息与进度），
    // 窄窗与移动端回退"封面⇄歌词"切换式；两套布局共用同一份视图与状态代码。
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    final m3eColors = M3ETheme.of(context).colors;
    return Scaffold(
      // 背景由 [_PlayerBackdrop]（封面主色三停渐变）承担（1.99.30 起永远渐变：
      // 根层已无 BackgroundLayer 可透出）
      backgroundColor: m3eColors.surface,
      extendBodyBehindAppBar: true,
      // 1.99.38：全屏播放页顶栏统一到 M3EAppBar；压在渐变上时返回键用
      // surfaceContainerHighest 色调圆底保证对比度，动作区用标准图标钮。
      appBar: M3EAppBar.small(
        topInset: MediaQuery.paddingOf(context).top,
        backgroundColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        title: const SizedBox.shrink(),
        leading: M3EIconButton(
          icon: Icons.keyboard_arrow_down,
          tooltip: '收起',
          onPressed: () => Navigator.of(context).pop(),
          backgroundColor:
              m3eColors.surfaceContainerHighest.withValues(alpha: 0.92),
        ),
        actions: [
          // 收藏（1.99.17，仅在线专辑）：复用在线「我的歌单」收藏体系
          if (album.isOnline &&
              OnlineWork.workIdFromAlbumId(album.id) != null)
            _PlayerFavoriteButton(
              workId: OnlineWork.workIdFromAlbumId(album.id)!,
              workTitle: album.title,
            ),
          // 跳详情（1.99.17，在线/本地通用）：关播放页开详情，播放不中断
          M3EIconButton(
            icon: Icons.info_outline_rounded,
            tooltip: album.isOnline ? '作品详情' : '专辑详情',
            onPressed: () => _openAlbumDetail(album),
          ),
          // 歌词/封面切换按钮（仅窄窗切换式需要；宽屏并排两块同屏无切换概念）
          if (!wide)
            M3EIconButton(
              icon: _showLyrics ? Icons.album : Icons.lyrics,
              tooltip: _showLyrics ? '显示封面' : '显示歌词',
              onPressed: () => _setShowLyrics(!_showLyrics),
            ),
        ],
      ),
      body: Stack(
        children: [
          // 封面主色三停渐变背景
          Positioned.fill(
            child: _PlayerBackdrop(album: album, playing: state.playing),
          ),
          SafeArea(
            child: Column(
              children: [
                // 中央区域：宽屏并排 / 窄窗切换（220ms 交叉淡入淡出）
                if (!wide) const SizedBox(height: 12),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 左：封面区（曲名与进度落在封面下方，构成独立锚点块）
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _buildCoverArea(
                                      album,
                                      state.playing,
                                      heroTag: widget.heroTag,
                                    ),
                                  ),
                                  _buildTrackInfo(album, track, theme, isDark),
                                  const SizedBox(height: 12),
                                  _buildProgressBar(position, duration, theme, isDark),
                                ],
                              ),
                            ),
                            // 右：歌词区（更宽，自动跟随+点句跳播）
                            Expanded(
                              child: _buildLyricsView(theme, isDark, allowToggle: false),
                            ),
                          ],
                        )
                      : AnimatedSwitcher(
                          // 中央区切换器挂专用 key：测试定位用（M3EFab 内也有
                          // AnimatedSwitcher，byType 会撞车，1.99.29）
                          key: const ValueKey('player-central-switcher'),
                          duration: M3ETheme.of(context)
                              .motion
                              .duration(
                                M3ESpringType.spatial,
                                M3ESpringSpeed.fast,
                              ),
                          child: _showLyrics
                              ? KeyedSubtree(
                                  key: const ValueKey('lyrics'),
                                  child: _buildLyricsView(theme, isDark),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('cover'),
                                  child: _buildCoverArea(
                                    album,
                                    state.playing,
                                    heroTag: widget.heroTag,
                                  ),
                                ),
                        ),
                ),
                const SizedBox(height: 16),
                // 曲目信息与进度条：宽屏时已并入左侧封面块
                if (!wide) ...[
                  _buildTrackInfo(album, track, theme, isDark),
                  const SizedBox(height: 12),
                  _buildProgressBar(position, duration, theme, isDark),
                  const SizedBox(height: 12),
                ],
                // 播放控制（通栏）
                _buildPlaybackControls(state, theme, isDark),
                const SizedBox(height: 8),
                // 辅助区（M3EToolbar）
                _buildFunctionButtons(state, settings, theme, isDark),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
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

  /// 点某句歌词：跳播到该句开头并立即居中（1.76.0，对齐详情页歌词 tab）。
  ///
  /// 与拖进度条 onChangeEnd 同语义——「我要跳到那一刻」，落地即恢复跟随并
  /// 重置滚动记账，否则用户手动滑走过歌词时会停在原处等下一句才自愈。
  void _seekToLine(int index) {
    final lines = ref.read(lyricsProvider).lines;
    if (index < 0 || index >= lines.length) return;
    HapticFeedback.selectionClick();
    ref
        .read(playbackProvider.notifier)
        .seek(lines[index].startTime.inMilliseconds / 1000.0);
    ref.read(lyricsProvider.notifier).resumeAutoScroll();
    setState(() => lastRevealedIndex = -1);
  }

  /// 中央封面区：320dp 大封面、角 28，播放态 28↔32 形变 + 缩放（plan §8.5）。
  ///
  /// [allowToggle] 为 false（1.83 宽屏并排模式）时点按不切歌词。
  Widget _buildCoverArea(
    Album album,
    bool isPlaying, {
    bool allowToggle = true,
    String? heroTag,
  }) {
    return GestureDetector(
      // 铺满整个中央区域：封面之外的留白点到也切歌词
      behavior: HitTestBehavior.opaque,
      onTap: allowToggle ? () => _setShowLyrics(true) : null,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
            child: AspectRatio(
              aspectRatio: 1,
              child: _MorphingHeroCover(
                album: album,
                playing: isPlaying,
                heroTag: heroTag,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 歌词视图（带自动滚动）
  ///
  /// [allowToggle] 为 false（1.83 宽屏并排模式）时留白点按不切唱片。
  Widget _buildLyricsView(ThemeData theme, bool isDark, {bool allowToggle = true}) {
    final lyrics = ref.watch(lyricsProvider);
    final settings = ref.watch(settingsProvider);

    if (!lyrics.hasLyrics) {
      // 无歌词时整个中央区可点回唱片层，与有歌词时的留白手势同语义
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: allowToggle ? () => _setShowLyrics(false) : null,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '暂无歌词',
                style: context.m3eType.titleMedium.copyWith(
                  color: context.m3eColors.onSurfaceVariant,
                ),
              ),
              // 宽屏并排模式下没有"返回唱片"概念，提示文案随之隐藏
              if (allowToggle) ...[
                const SizedBox(height: 8),
                Text(
                  '点击返回唱片',
                  style: context.m3eType.bodySmall.copyWith(
                    color: context.m3eColors.onSurfaceVariant
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
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
              onTap: allowToggle ? () => _setShowLyrics(false) : null,
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
                  return Padding(
                    key: _lineKeys.putIfAbsent(index, () => GlobalKey()),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    // 手势分层（1.73/1.75/1.76 语义）：点歌词文字=跳播该句
                    // （仅限文字渲染框），行间空隙与首末句之外留白=回唱片层，
                    // 拖动滚动由竞技场判给 ListView，不会误触点击。
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _seekToLine(index),
                      child: Text(
                        line.text,
                        textAlign: TextAlign.center,
                        // 歌词字号**故意不用 type 角色**：它和
                        // `lyricsEstimatedLineHeight = 45 × lyricsFontScale`
                        // 是一对承重 metrics（居中/自动滚动按它粗定位）。
                        // 换角色就得同步改估算行高，否则远跳会多滚半屏。
                        style: TextStyle(
                          fontSize: (isCurrent ? 18 : 15) * lyricsFontScale,
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: isCurrent
                              ? context.m3eColors.onSurface
                              : context.m3eColors.onSurfaceVariant,
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
                  onPressed: () =>
                      _showLyricsFontScaleDialog(settings),
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
            style: context.m3eType.titleLargeEmphasized.copyWith(
              color: context.m3eColors.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            album.artist,
            style: context.m3eType.bodyMedium.copyWith(
              color: context.m3eColors.onSurfaceVariant,
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
    required VoidCallback onPressed,
  }) {
    // 1.99.46：自绘黑白半透明胶囊 + Material IconButton → M3EIconButton.tonal
    // （压在歌词上，用 tonal 底色保证任何封面配色下都读得出来）
    return M3EIconButton(
      icon: icon,
      tooltip: tooltip,
      size: M3EIconButtonSize.small,
      variant: M3EIconButtonVariant.tonal,
      onPressed: onPressed,
    );
  }

  /// 进度条（M3ESlider：16dp 粗轨道 + 4×44 把手，plan §8.5）
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
          M3ESlider(
            key: const ValueKey('player-progress-slider'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatTime(displayPosition),
                  style: context.m3eType.labelMedium.copyWith(
                    color: context.m3eColors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  formatTime(duration),
                  style: context.m3eType.labelMedium.copyWith(
                    color: context.m3eColors.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 播放控制（M3E，plan §8.5）：M3EFab.large 主键 + 次键图标按钮
  Widget _buildPlaybackControls(dynamic state, ThemeData theme, bool isDark) {
    final colors = M3ETheme.of(context).colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一曲
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 36),
          color: colors.onSurface,
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(playbackProvider.notifier).prev();
          },
        ),
        const SizedBox(width: 20),
        // 播放/暂停：M3EFab.large（96dp / 角 28），图标随状态切换
        M3EFab(
          semanticLabel: state.playing ? '暂停' : '播放',
          onPressed: () {
            HapticFeedback.mediumImpact(); // 主按钮使用更强烈的反馈
            ref.read(playbackProvider.notifier).toggle();
          },
          child: AnimatedSwitcher(
            duration: M3ETheme.of(context)
                .motion
                .duration(M3ESpringType.effects, M3ESpringSpeed.normal),
            child: Icon(
              state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(state.playing),
            ),
          ),
        ),
        const SizedBox(width: 20),
        // 下一曲
        IconButton(
          icon: const Icon(Icons.skip_next, size: 36),
          color: colors.onSurface,
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(playbackProvider.notifier).next();
          },
        ),
      ],
    );
  }

  /// 辅助区（M3EToolbar 全圆浮动，plan §8.5）：定时 / 增益 / 音量(桌面) /
  /// 悬浮歌词(桌面) / 倍速(Android) / 播放模式 / 列表。
  ///
  /// 1.99.29 起播放条不再承载这些入口（对齐移动端 1.99.7 形态），
  /// 本区是唯一归宿；桌面端因此补了「音量」与「悬浮歌词」两键。
  Widget _buildFunctionButtons(
    dynamic state,
    AppSettings settings,
    ThemeData theme,
    bool isDark,
  ) {
    final isDesktop =
        !Platform.isAndroid && !Platform.isIOS; // macOS / Windows
    return M3EToolbar(
      margin: const EdgeInsets.fromLTRB(40, 0, 40, 0),
      // 桌面端 7 个动作在窄窗会超出 64dp 工具条宽度，横向滚动兜底；
      // 宽窗下从左排布（M3E 工具条惯例），不强行 spaceEvenly。
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          // 睡眠定时
          _ToolbarAction(
            icon: Icons.bedtime_outlined,
            tooltip: '睡眠定时',
            active: state.sleepMode != SleepTimerMode.off,
            onTap: () => _showSleepTimerDialog(),
          ),
          // 音频增益
          _ToolbarAction(
            icon: Icons.graphic_eq_rounded,
            tooltip: '音频增益',
            active: settings.audioGain > 1.0,
            onTap: () => _showGainDialog(settings),
          ),
          // 音量（桌面：播放条音量键 1.99.29 移入此处）
          if (isDesktop) _buildVolumeToolbarButton(settings, theme),
          // 桌面悬浮歌词（桌面专属）
          if (isDesktop) _buildDesktopLyricsToolbarButton(theme),
          // 倍速（仅 Android，1.99.7 起）
          if (Platform.isAndroid)
            _ToolbarAction(
              icon: Icons.speed_outlined,
              tooltip: '播放倍速 ${settings.playbackRate.toStringAsFixed(1)}x',
              active: settings.playbackRate != 1.0,
              onTap: () => _showRateDialog(settings),
            ),
          // 播放模式
          _buildPlayModeToolbarButton(state.mode),
          // 音轨列表
          _ToolbarAction(
            icon: Icons.queue_music_outlined,
            tooltip: '曲目列表',
            onTap: () => _showTrackListSheet(state.album, state.queueIndex),
          ),
          ],
        ),
      ),
    );
  }

  /// 音量弹出菜单（音量滑杆；增益有自己的对话框，不在这里混）
  Widget _buildVolumeToolbarButton(AppSettings settings, ThemeData theme) {
    // 1.99.46：`MenuAnchor` + Material `Slider` → `M3EMenu` + `M3EMenuCustom`
    // + `M3ESlider`。滑杆行不给 onTap，拖动时菜单不会关。
    return M3EMenu(
      maxWidth: 220,
      alignmentOffset: const Offset(0, -12),
      builder: (context, controller, child) => _ToolbarAction(
        icon: settings.volume == 0
            ? Icons.volume_off_rounded
            : settings.volume < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded,
        tooltip: '音量 ${(settings.volume * 100).round()}%',
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      children: <Widget>[
        M3EMenuCustom(
          minHeight: 76,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          // 不给 onTap：拖滑杆时菜单保持打开
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${(settings.volume * 100).round()}%',
                style: context.m3eType.labelLarge.copyWith(
                  color: context.m3eColors.primary,
                ),
              ),
              M3ESlider(
                key: const ValueKey('volume-slider'),
                value: settings.volume,
                max: 1,
                onChanged: (v) {
                  ref.read(settingsProvider.notifier).setVolume(v);
                  ref.read(playbackProvider.notifier).setVolume(v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 桌面悬浮歌词开关（含右键锁定菜单，1.99.29 自播放条移入）
  Widget _buildDesktopLyricsToolbarButton(ThemeData theme) {
    final status = ref.watch(desktopLyricsProvider);
    final notifier = ref.read(desktopLyricsProvider.notifier);
    final isShowing = status.isShowing;
    final isLocked = status.isLocked;

    return M3EMenu(
      maxWidth: 280,
      builder: (context, controller, child) => GestureDetector(
        onSecondaryTapDown: (details) {
          if (isShowing) controller.open(position: details.localPosition);
        },
        child: _ToolbarAction(
          icon: isShowing
              ? Icons.chat_bubble_rounded
              : Icons.chat_bubble_outline_rounded,
          tooltip: !isShowing
              ? '开启桌面悬浮歌词'
              : isLocked
                  ? '桌面歌词已锁定（点击解锁）'
                  : '关闭桌面悬浮歌词（右键可锁定）',
          active: isShowing,
          onTap: () async {
            if (isLocked) {
              await notifier.setLocked(false);
              if (mounted) {
                showHikoToast(this.context, '已解除桌面歌词鼠标锁定',
                    duration: kDesktopLyricsToastLinger);
              }
            } else {
              final active = await notifier.toggle();
              if (mounted) {
                showHikoToast(
                    this.context, active ? '已开启桌面悬浮歌词' : '已关闭桌面悬浮歌词',
                    duration: kDesktopLyricsToastLinger);
              }
            }
          },
        ),
      ),
      children: <Widget>[
        M3EMenuAction(
          label: isLocked ? '解除悬浮窗锁定' : '锁定悬浮窗（穿透鼠标）',
          leadingIcon: isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
          onPressed: () async {
            await notifier.setLocked(!isLocked);
            if (mounted) {
              showHikoToast(this.context,
                  !isLocked ? '已锁定桌面歌词（鼠标点击穿透）' : '已解除桌面歌词锁定',
                  duration: kDesktopLyricsToastLinger);
            }
          },
        ),
        M3EMenuAction(
          label: '关闭桌面歌词',
          leadingIcon: Icons.close_rounded,
          onPressed: () async {
            await notifier.hide();
            if (mounted) {
              showHikoToast(this.context, '已关闭桌面悬浮歌词',
                  duration: kDesktopLyricsToastLinger);
            }
          },
        ),
      ],
    );
  }

  /// 播放模式按钮（图标态 + M3E 菜单）
  Widget _buildPlayModeToolbarButton(PlaybackMode currentMode) {
    final modeInfo = playModes.firstWhere((m) => m.key == currentMode.key);
    final IconData icon = switch (currentMode) {
      PlaybackMode.list => Icons.repeat_outlined,
      PlaybackMode.single => Icons.repeat_one_outlined,
      PlaybackMode.shuffle => Icons.shuffle_outlined,
      PlaybackMode.album => Icons.album,
    };

    return M3EMenu(
      maxWidth: 280,
      builder: (context, controller, child) => _ToolbarAction(
        icon: icon,
        tooltip: '播放模式：${modeInfo.label}',
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      children: <Widget>[
        const M3EMenuHeader(label: '播放模式'),
        const M3EMenuDivider(),
        // 四种播放模式选项
        for (final mode in PlaybackMode.values)
          _buildPlayModeMenuItem(mode, currentMode),
      ],
    );
  }

  /// 单个播放模式菜单项（名称 + 一行说明 + 选中勾）
  Widget _buildPlayModeMenuItem(
    PlaybackMode mode,
    PlaybackMode currentMode,
  ) {
    final info = playModes.firstWhere((m) => m.key == mode.key);
    final isSelected = mode == currentMode;

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

    return M3EMenuAction(
      label: info.name,
      subtitle: info.desc,
      leadingIcon: leadingIcon,
      selected: isSelected,
      onPressed: () async {
        HapticFeedback.selectionClick();
        // 1.99.58：原来的 `setPlayMode(mode.key)` 只是往 AppSettings 写一个
        // **没有任何读取方**的字段（退出重进不会恢复），随死设置一并删除。
        await ref.read(playbackProvider.notifier).setMode(mode);
      },
    );
  }

  /// 歌词字号调节对话框（1.99.42：RadioListTile → M3EListItem）
  Future<void> _showLyricsFontScaleDialog(AppSettings settings) async {
    final scales = [
      (0.85, '小'),
      (1.0, '标准'),
      (1.15, '大'),
      (1.30, '超大'),
      (1.50, '巨大'),
    ];

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return M3EDialog(
          maxWidth: 420,
          title: '歌词字号',
          scrollable: false,
          contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          content: M3EList(
            children: <Widget>[
              for (final (scale, label) in scales)
                M3EListItem(
                  title: label,
                  subtitle: '×${scale.toStringAsFixed(2)}',
                  selected: settings.lyricsFontScale == scale,
                  onTap: () {
                    ref.read(settingsProvider.notifier).setLyricsFontScale(scale);
                    Navigator.pop(dialogContext);
                    showHikoToast(context, '歌词字号已设为 $label');
                  },
                ),
            ],
          ),
          actions: <Widget>[
            M3EButton(
              label: '取消',
              variant: M3EButtonVariant.text,
              onPressed: () => Navigator.pop(dialogContext),
            ),
          ],
        );
      },
    );
  }

  /// 睡眠定时对话框：预设档 + 自定义分钟滑杆（松手生效）+ 曲终/专辑终停
  Future<void> _showSleepTimerDialog() async {
    final state = ref.read(playbackProvider);
    final sleepMode = state.sleepMode;
    final sleepRemaining = state.sleepRemaining;
    int customMin = 30;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = M3ETheme.of(context);
          final colors = theme.colors;
          return M3EDialog(
            title: '睡眠定时',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (sleepMode == SleepTimerMode.timed && sleepRemaining != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      '剩余 ${(sleepRemaining.inMinutes + 1)} 分钟',
                      style: theme.type.titleSmall.copyWith(color: colors.primary),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final min in const [5, 10, 15, 30, 45, 60])
                      M3EButton(
                        label: '$min 分钟',
                        variant: M3EButtonVariant.tonal,
                        size: M3EButtonSize.small,
                        onPressed: () {
                          ref
                              .read(playbackProvider.notifier)
                              .setSleepMinutes(min);
                          Navigator.pop(dialogContext);
                          showHikoToast(this.context, '已设置 $min 分钟后停止播放');
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '自定义：$customMin 分钟',
                  style: theme.type.labelLarge.copyWith(color: colors.primary),
                ),
                Slider(
                  value: customMin.toDouble(),
                  min: 5,
                  max: 240,
                  divisions: 47,
                  label: '$customMin 分钟',
                  onChanged: (v) => setDialogState(() => customMin = v.round()),
                  onChangeEnd: (v) {
                    ref
                        .read(playbackProvider.notifier)
                        .setSleepMinutes(v.round());
                    Navigator.pop(dialogContext);
                    showHikoToast(
                        this.context, '已设置 ${v.round()} 分钟后停止播放');
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    M3EButton(
                      label: '播完当前曲',
                      variant: M3EButtonVariant.text,
                      size: M3EButtonSize.small,
                      onPressed: () {
                        ref
                            .read(playbackProvider.notifier)
                            .setSleepEndOfTrack();
                        Navigator.pop(dialogContext);
                        showHikoToast(this.context, '将在播完当前曲后停止');
                      },
                    ),
                    M3EButton(
                      label: '播完当前专辑',
                      variant: M3EButtonVariant.text,
                      size: M3EButtonSize.small,
                      onPressed: () {
                        ref
                            .read(playbackProvider.notifier)
                            .setSleepEndOfAlbum();
                        Navigator.pop(dialogContext);
                        showHikoToast(this.context, '将在播完当前专辑后停止');
                      },
                    ),
                  ],
                ),
                if (sleepMode != SleepTimerMode.off)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: M3EButton(
                      label: '取消定时',
                      variant: M3EButtonVariant.text,
                      size: M3EButtonSize.small,
                      onPressed: () {
                        ref.read(playbackProvider.notifier).setSleepOff();
                        Navigator.pop(dialogContext);
                        showHikoToast(this.context, '已取消定时');
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 音频增益对话框。1.99.15：当前为本地专辑时写「按专辑记忆」，全局设置不动。
  Future<void> _showGainDialog(AppSettings settings) async {
    final album = ref.read(playbackProvider).album;
    final albumScoped = album != null && !album.isOnline;
    double tempGain = album?.gainOverride ?? settings.audioGain;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = M3ETheme.of(context);
          final colors = theme.colors;
          return M3EDialog(
            title: '音频增益',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'x${tempGain.toStringAsFixed(1)}',
                  style: theme.type.headlineSmall.copyWith(color: colors.primary),
                ),
                const SizedBox(height: 16),
                if (albumScoped) ...<Widget>[
                  Text(
                    album.gainOverride != null
                        ? '将记忆到本专辑（当前 x${album.gainOverride!.toStringAsFixed(1)}）'
                        : '将记忆到本专辑（全局 x${settings.audioGain.toStringAsFixed(1)} 不受影响）',
                    textAlign: TextAlign.center,
                    style: theme.type.bodySmall.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                // 带档位的滑杆等 M3ESlider 支持 divisions 后再换（1.99.46）
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
                  textAlign: TextAlign.center,
                  style: theme.type.bodySmall.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: <Widget>[
              if (albumScoped && album.gainOverride != null)
                M3EButton(
                  label: '清除专辑记忆',
                  variant: M3EButtonVariant.text,
                  onPressed: () {
                    ref
                        .read(playbackProvider.notifier)
                        .clearAlbumPlaybackMemory();
                    Navigator.pop(dialogContext);
                    showHikoToast(context, '已清除本专辑增益记忆');
                  },
                ),
              M3EButton(
                label: '取消',
                variant: M3EButtonVariant.text,
                onPressed: () => Navigator.pop(dialogContext),
              ),
              M3EButton(
                label: '确定',
                onPressed: () {
                  final controller = ref.read(playbackProvider.notifier);
                  if (albumScoped) {
                    controller.setAlbumGain(tempGain);
                  } else {
                    ref.read(settingsProvider.notifier).setAudioGain(tempGain);
                    controller.setAudioGain(tempGain);
                  }
                  Navigator.pop(dialogContext);
                  showHikoToast(
                      context, '增益已设为 x${tempGain.toStringAsFixed(1)}');
                },
              ),
            ],
          );
        },
      ),
    );
  }

  /// 倍速对话框（仅 Android，1.99.7）：0.5~2.0 步进 0.1，拖动松手即生效。
  /// 1.99.15：当前为本地专辑时写「按专辑记忆」，全局设置不动；有记忆时显示清除入口。
  Future<void> _showRateDialog(AppSettings settings) async {
    final album = ref.read(playbackProvider).album;
    final albumScoped = album != null && !album.isOnline;
    final initial = album?.playbackRateOverride ?? settings.playbackRate;
    double tempRate = initial;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = M3ETheme.of(context);
          final colors = theme.colors;
          return M3EDialog(
            title: '播放倍速',
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'x${tempRate.toStringAsFixed(1)}',
                  style: theme.type.headlineSmall.copyWith(color: colors.primary),
                ),
                if (albumScoped) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    album.playbackRateOverride != null
                        ? '将记忆到本专辑（当前 x${album.playbackRateOverride!.toStringAsFixed(1)}）'
                        : '将记忆到本专辑（全局 x${settings.playbackRate.toStringAsFixed(1)} 不受影响）',
                    textAlign: TextAlign.center,
                    style: theme.type.bodySmall.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                // 带档位的滑杆等 M3ESlider 支持 divisions 后再换（1.99.46）
                Slider(
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  value: tempRate.clamp(0.5, 2.0),
                  label: 'x${tempRate.toStringAsFixed(1)}',
                  onChanged: (v) =>
                      setDialogState(() => tempRate = (v * 10).round() / 10),
                  onChangeEnd: (v) {
                    final r = (v * 10).round() / 10;
                    final controller = ref.read(playbackProvider.notifier);
                    if (albumScoped) {
                      controller.setAlbumPlaybackRate(r);
                    } else {
                      // setPlaybackRate 内部落设置持久化
                      controller.setPlaybackRate(r);
                    }
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text('0.5x', style: theme.type.labelSmall),
                    if (albumScoped && album.playbackRateOverride != null)
                      M3EButton(
                        label: '清除专辑记忆',
                        variant: M3EButtonVariant.text,
                        size: M3EButtonSize.small,
                        onPressed: () {
                          setDialogState(
                              () => tempRate = settings.playbackRate);
                          ref
                              .read(playbackProvider.notifier)
                              .clearAlbumPlaybackMemory();
                        },
                      )
                    else
                      M3EButton(
                        label: '恢复 1.0x',
                        variant: M3EButtonVariant.text,
                        size: M3EButtonSize.small,
                        onPressed: () {
                          setDialogState(() => tempRate = 1.0);
                          if (albumScoped) {
                            ref
                                .read(playbackProvider.notifier)
                                .setAlbumPlaybackRate(1.0);
                          } else {
                            ref
                                .read(playbackProvider.notifier)
                                .setPlaybackRate(1.0);
                          }
                        },
                      ),
                    Text('2.0x', style: theme.type.labelSmall),
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              M3EButton(
                label: '关闭',
                variant: M3EButtonVariant.text,
                onPressed: () => Navigator.pop(dialogContext),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 1.99.17「跳详情」；1.99.18 起**全平台**统一走指令通道（桌面/移动不再分叉）：
  /// 播放页只发请求 + 关自己，详情由 home（本地抽屉 / 移动整页，在线则切到
  /// 在线页由 OnlineScreen 打开）打开 —— 那些详情才带着完整的筛选回调，播放页
  /// 裸 push 的详情页点社团/声优是死的（1.99.18 实测反馈）。播放不中断。
  ///
  /// 注意顺序：**先 pop 再发请求**。请求会被宿主的 ref.listen 同步消费，
  /// 移动端本地路径会在监听里 push 详情页——若先发请求，随后本页的 pop
  /// 会把刚 push 的详情顶掉。
  void _openAlbumDetail(Album album) {
    final nav = Navigator.of(context);
    final localReq = ref.read(localDetailRequestProvider.notifier);
    final onlineReq = ref.read(onlineDetailRequestProvider.notifier);
    nav.pop();
    if (album.isOnline) {
      final workId = OnlineWork.workIdFromAlbumId(album.id);
      if (workId == null) return;
      onlineReq.state = workId;
    } else {
      localReq.state = album.id;
    }
  }

  /// 音轨列表底部弹窗
  Future<void> _showTrackListSheet(Album? album, int currentIndex) async {
    if (album == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      // 底色交给 M3ESheet（色调面 + 28 顶角 + 海拔），这里只负责路由与手势
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) {
          final colors = context.m3eColors;
          final type = context.m3eType;
          return M3ESheet(
            variant: M3ESheetVariant.bottom,
            child: Column(
              children: <Widget>[
                const SizedBox(height: 12),
                // 拖拽把手
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: M3EShape.radius(M3EShape.full),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: <Widget>[
                      Text('播放列表', style: type.titleMedium),
                      const Spacer(),
                      Text(
                        '共 ${album.tracks.length} 首',
                        style: type.bodySmall.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
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
                      return M3EListItem(
                        title: track.name,
                        selected: isCurrent,
                        leading: isCurrent
                            ? Icon(Icons.volume_up_rounded, color: colors.primary)
                            : Text(
                                '${index + 1}',
                                textAlign: TextAlign.center,
                                style: type.labelMedium.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                        trailing: Text(
                          formatTime(track.duration),
                          style: type.labelMedium.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        onTap: () {
                          ref
                              .read(playbackProvider.notifier)
                              .playAlbum(album, index: index);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 播放页的收藏按钮（1.99.17，仅在线专辑显示）。
///
/// 复用在线「我的歌单」收藏体系：点按弹多选歌单弹窗（与详情页同一流程）。
/// 点亮状态直接读本地收藏索引（登录恢复时已拉过），不为一个图标单独发请求；
/// 未登录点按走登录引导，登录态恢复期间禁用（与详情页收藏按钮同语义）。
class _PlayerFavoriteButton extends ConsumerWidget {
  const _PlayerFavoriteButton({required this.workId, required this.workTitle});

  final int workId;
  final String workTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(onlineAccountProvider);
    final collected = ref
        .watch(onlineFavoritesProvider
            .select((s) => s.index.playlistsOf(workId)))
        .isNotEmpty;

    final onPressed = !account.loggedIn
        ? (account.settled
            ? () => unawaited(
                  showLoginRequiredDialog(context, action: '收藏作品'),
                )
            : null)
        : () => unawaited(showPlaylistPicker(
              context,
              // 播放态里没有 OnlineWork 实体：弹窗链路只消费 id / title
              //（applyLocal 落索引后本就有一次后台刷新补全其余字段）
              work: OnlineWork(id: workId, title: workTitle),
            ));

    return M3EIconButton(
      onPressed: onPressed,
      tooltip: collected ? '已收藏 · 编辑歌单' : '收藏',
      icon: collected ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      foregroundColor: collected ? M3ESemantic.favorite : null,
    );
  }
}

/// 播放页封面：角 28 ↔ 32 + scale 1.0 ↔ 0.98 的播放态形变（spatialSlow 弹簧）。
///
/// 实现约束（plan §7.4）：圆角插值 + Transform.scale 近似，不走 layout 动画；
/// 动效关闭时不创建动画路径，直接到终态。挂 [heroTag] 时参与路由 Hero 转场
/// （英雄时刻 A），飞行途中圆角从来源侧 16 连续插值到目标侧 28。
class _MorphingHeroCover extends StatefulWidget {
  const _MorphingHeroCover({
    required this.album,
    required this.playing,
    this.heroTag,
  });

  final Album album;
  final bool playing;
  final String? heroTag;

  @override
  State<_MorphingHeroCover> createState() => _MorphingHeroCoverState();
}

class _MorphingHeroCoverState extends State<_MorphingHeroCover>
    with SingleTickerProviderStateMixin {
  /// t：0 = 暂停态（角 28 / scale 1.0），1 = 播放态（角 32 / scale 0.98）。
  late final AnimationController _t = AnimationController.unbounded(
    vsync: this,
    value: widget.playing ? 1 : 0,
  );

  @override
  void didUpdateWidget(_MorphingHeroCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      _animate(widget.playing ? 1 : 0);
    }
  }

  void _animate(double target) {
    final motion = M3ETheme.of(context).motion;
    if (!motion.enabled) {
      _t.value = target;
      return;
    }
    if (motion.level == M3EMotionLevel.reduced) {
      _t.animateTo(
        target,
        duration: motion.duration(M3ESpringType.spatial, M3ESpringSpeed.slow),
        curve: motion.fallbackCurve,
      );
      return;
    }
    _t.animateWith(
      SpringSimulation(
        motion.spring(M3ESpringType.spatial, M3ESpringSpeed.slow),
        _t.value,
        target,
        0,
      ),
    );
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final t = _t.value;
        final radius = M3EShape.xl + (M3EShape.xlPlus - M3EShape.xl) * t;
        final scale = 1.0 - 0.02 * t;
        Widget cover = ClipRRect(
          borderRadius: M3EShape.radius(radius),
          child: AlbumCover(album: widget.album, fit: BoxFit.cover),
        );
        if (widget.heroTag != null) {
          // 默认 Hero 飞行：目标子树（角 28）从来源位置/尺寸飞入。
          // 不做自绘圆角插值——链式第二跳（详情 28 → 播放页 28）反而会被
          // 「先回到 16 再到 28」的自定义插值弄出折返感。
          cover = Hero(tag: widget.heroTag!, child: cover);
        }
        return Transform.scale(scale: scale, child: cover);
      },
    );
  }
}

/// 播放页背景：封面主色 → 纵向三停渐变（plan §8.5，不是模糊）。
///
/// 播放中做 ±2% 明度呼吸：唯一的持续动画，颜色走 RepaintBoundary 内的重绘，
/// 「减弱/关闭」动效档与系统 reduce-motion 下不起。
class _PlayerBackdrop extends StatefulWidget {
  const _PlayerBackdrop({required this.album, required this.playing});

  final Album album;
  final bool playing;

  @override
  State<_PlayerBackdrop> createState() => _PlayerBackdropState();
}

class _PlayerBackdropState extends State<_PlayerBackdrop>
    with SingleTickerProviderStateMixin {
  Color? _base;

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: kBackdropBreathDuration,
  );

  @override
  void initState() {
    super.initState();
    _loadColor();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreath();
  }

  @override
  void didUpdateWidget(_PlayerBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id) _loadColor();
    _syncBreath();
  }

  void _loadColor() {
    final source = widget.album.currentCover ?? widget.album.localCover;
    _base = null;
    CoverColor.of(coverSource: source).then((color) {
      if (mounted && source != null) {
        setState(() => _base = color);
      }
    });
  }

  void _syncBreath() {
    final motion = M3ETheme.of(context).motion;
    final shouldRun = widget.playing &&
        motion.level == M3EMotionLevel.full &&
        !MediaQuery.disableAnimationsOf(context);
    if (shouldRun && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
    } else if (!shouldRun && _breath.isAnimating) {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // 主色未就绪/无封面时用主题容器色兜底，不闪白
    final base = _base ?? colors.primaryContainer;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _breath,
        builder: (context, child) {
          // ±2% 明度呼吸：base 在「微暗 ↔ 微亮」两端间往返
          final lo = Color.lerp(base, Colors.black, 0.02)!;
          final hi = Color.lerp(base, Colors.white, 0.02)!;
          final current = Color.lerp(lo, hi, _breath.value)!;
          final top = Color.lerp(current, Colors.black, dark ? 0.5 : 0.2)!;
          final mid = Color.lerp(
            current,
            dark ? M3ESemantic.artworkVignette : Colors.white,
            0.72,
          )!;
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [top, mid, colors.surface],
                stops: const [0, 0.5, 1],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 辅助工具条上的图标动作（icon-only + tooltip，激活态用主题色）。
class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    // 1.99.46：Material 图标钮 → M3EIconButton（选中态 = secondaryContainer 底 +
    // primary 图标；以前只有图标换色，看不出「这个开关现在是开的」）
    return M3EIconButton(
      icon: icon,
      tooltip: tooltip,
      onPressed: onTap,
      selected: active,
    );
  }
}

/// 播放页的 M3E 取值口（1.99.46）。
///
/// 这一页的文字压在封面渐变上，以前靠 `HikoColors.darkInk/lightInk` 之类的
/// 旧 token 手挑颜色；收口后一律 `onSurface` / `onSurfaceVariant`
/// （渐变底已经由 `surface` 色罩压暗，对比度由色阶保证）。
extension _PlayerTheme on BuildContext {
  M3EColors get m3eColors => M3ETheme.of(this).colors;
  M3EType get m3eType => M3ETheme.of(this).type;
}
