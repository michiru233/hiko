import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../models/album.dart';
import '../../playback/gain_chain.dart';
import '../../playback/playback_controller.dart';
import '../../playback/sleep_timer.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
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

class _FullscreenPlayerScreenState
    extends ConsumerState<FullscreenPlayerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  bool _showLyrics = false;
  bool _dragging = false;
  double _dragValue = 0;

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

    // 同步旋转动画与播放状态
    if (state.playing && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!state.playing && _rotationController.isAnimating) {
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
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
            tooltip: _showLyrics ? '显示封面' : '显示歌词',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 中央区域：黑胶唱片层或歌词层
            Expanded(
              child: _showLyrics
                  ? _buildLyricsView(theme, isDark)
                  : _buildVinylView(album, theme, isDark, state.playing),
            ),
            const SizedBox(height: 24),
            // 曲目信息
            _buildTrackInfo(album, track, theme, isDark),
            const SizedBox(height: 20),
            // 进度条
            _buildProgressBar(position, duration, theme, isDark),
            const SizedBox(height: 20),
            // 播放控制
            _buildPlaybackControls(state, theme, isDark),
            const SizedBox(height: 16),
            // 三核心功能键
            _buildFunctionButtons(state, settings, theme, isDark),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 黑胶唱片视图：封面旋转 + 唱针联动
  Widget _buildVinylView(
    Album album,
    ThemeData theme,
    bool isDark,
    bool isPlaying,
  ) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 旋转的黑胶唱片
          AnimatedBuilder(
            animation: _rotationController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _rotationController.value * 2 * math.pi,
                child: child,
              );
            },
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipOval(
                child: AlbumCover(
                  album: album,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // 中心圆孔
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? HikoColors.darkBg : HikoColors.lightBg,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
                width: 2,
              ),
            ),
          ),
          // 唱针（右上角）
          Positioned(
            top: -20,
            right: 80,
            child: AnimatedRotation(
              duration: const Duration(milliseconds: 400),
              turns: isPlaying ? 0.05 : -0.05, // 播放时落下，暂停时抬起
              alignment: Alignment.topRight,
              child: Container(
                width: 80,
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      isDark ? Colors.grey[700]! : Colors.grey[400]!,
                      isDark ? Colors.grey[800]! : Colors.grey[500]!,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(2, 4),
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

  /// 歌词视图
  Widget _buildLyricsView(ThemeData theme, bool isDark) {
    final lyrics = ref.watch(lyricsProvider);
    if (!lyrics.hasLyrics) {
      return Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(
            fontSize: 16,
            color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
          ),
        ),
      );
    }

    final lines = lyrics.lines;
    final currentIndex = lyrics.activeIndex;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final isCurrent = index == currentIndex;
        final line = lines[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isCurrent ? 18 : 15,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              color: isCurrent
                  ? (isDark ? HikoColors.darkInk : HikoColors.lightInk)
                  : (isDark ? HikoColors.darkMuted : HikoColors.lightMuted),
              height: 1.8,
            ),
          ),
        );
      },
    );
  }

  /// 曲目信息
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
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            album.artist,
            style: TextStyle(
              fontSize: 14,
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

  /// 进度条
  Widget _buildProgressBar(
    double position,
    double duration,
    ThemeData theme,
    bool isDark,
  ) {
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
              value: duration > 0 ? position.clamp(0, duration) : 0,
              max: duration > 0 ? duration : 1,
              onChanged: (v) => setState(() {
                _dragging = true;
                _dragValue = v;
              }),
              onChangeEnd: (v) {
                ref.read(playbackProvider.notifier).seek(v);
                setState(() => _dragging = false);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatDuration(position),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                  ),
                ),
                Text(
                  formatDuration(duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
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
  Widget _buildPlaybackControls(
    dynamic state,
    ThemeData theme,
    bool isDark,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一曲
        IconButton(
          icon: const Icon(Icons.skip_previous, size: 36),
          color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
          onPressed: () => ref.read(playbackProvider.notifier).prev(),
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
            onPressed: () => ref.read(playbackProvider.notifier).toggle(),
          ),
        ),
        const SizedBox(width: 20),
        // 下一曲
        IconButton(
          icon: const Icon(Icons.skip_next, size: 36),
          color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
          onPressed: () => ref.read(playbackProvider.notifier).next(),
        ),
      ],
    );
  }

  /// 三核心功能键：睡眠定时、音频增益、音轨列表
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '共 ${album.tracks.length} 首',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
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
                                fontSize: 14,
                                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                                color: isCurrent
                                    ? theme.colorScheme.primary
                                    : (isDark ? HikoColors.darkInk : HikoColors.lightInk),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              formatDuration(track.duration),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? HikoColors.darkMuted
                                    : HikoColors.lightMuted,
                              ),
                            ),
                            onTap: () {
                              ref.read(playbackProvider.notifier).playAlbum(
                                    album,
                                    index: index,
                                  );
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
