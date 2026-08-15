import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../lyrics/desktop_lyrics_service.dart';
import '../../models/album.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_rules.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';

/// 底部播放条：封面 + 标题/艺人 + 控制 + 进度 + 播放模式 + 音量（对应旧版 footer.player）。
/// compact（移动端）为两行布局：控件在上，全宽进度条下移成一行。
class PlayerBar extends ConsumerStatefulWidget {
  const PlayerBar({super.key, this.onCoverTap, this.compact = false});

  /// 点击当前封面 → 打开详情
  final void Function(Album album)? onCoverTap;

  /// 移动端紧凑两行布局
  final bool compact;

  @override
  ConsumerState<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends ConsumerState<PlayerBar> {
  bool _dragging = false;
  double _dragValue = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final album = state.album;
    final track = state.currentTrack;

    final position = _dragging ? _dragValue : state.position;
    final duration = state.duration;

    final topRow = Row(
      children: [
        _buildCover(theme, album),
        const SizedBox(width: 12),
        // compact 窄屏：meta 必须弹性收缩，否则溢出
        widget.compact
            ? Expanded(child: _buildMeta(theme, state, album, track))
            : _buildMeta(theme, state, album, track),
        const SizedBox(width: 10),
        _buildControls(theme, state),
        const Spacer(),
        _buildModeButton(theme, state),
        const SizedBox(width: 12),
        if (Platform.isMacOS) ...[
          _buildDesktopLyricsButton(theme),
          const SizedBox(width: 12),
        ],
        _buildVolumeButton(theme, settings),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: EdgeInsets.symmetric(horizontal: widget.compact ? 12 : 26, vertical: 8),
      child: widget.compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                topRow,
                _buildTimeline(theme, position, duration),
              ],
            )
          : Row(
              children: [
                _buildCover(theme, album),
                const SizedBox(width: 15),
                _buildMeta(theme, state, album, track),
                const SizedBox(width: 18),
                _buildControls(theme, state),
                const SizedBox(width: 18),
                Expanded(child: _buildTimeline(theme, position, duration)),
                const SizedBox(width: 18),
                _buildModeButton(theme, state),
                if (Platform.isMacOS) ...[
                  const SizedBox(width: 14),
                  _buildDesktopLyricsButton(theme),
                ],
                const SizedBox(width: 14),
                _buildVolumeButton(theme, settings),
              ],
            ),
    );
  }

  // ---- 封面 ----
  Widget _buildCover(ThemeData theme, Album? album) {
    final size = widget.compact ? 40.0 : 48.0;
    return InkWell(
      onTap: album == null ? null : () => widget.onCoverTap?.call(album),
      mouseCursor: album == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: album == null
              ? Container(color: const Color(0xFFD5D1E8))
              : AlbumCover(album: album),
        ),
      ),
    );
  }

  // ---- 元信息 ----
  Widget _buildMeta(ThemeData theme, PlaybackState state, Album? album, track) {
    return SizedBox(
      width: widget.compact ? null : 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.compact) ...[
            Text(
              '正在播放',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
          ],
          Text(
            album == null
                ? '未在播放'
                : '${album.title} · ${state.queueIndex >= 0 ? (state.queueIndex + 1).toString().padLeft(2, '0') : '01'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(
            track == null ? '' : '${album?.artist ?? ''} · ${track.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  // ---- 播放控制（Material 图标，两端视觉统一；文字符号在部分 Android 字体渲染异常）----
  Widget _buildControls(ThemeData theme, PlaybackState state) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconButton(
          icon: Icons.skip_previous_rounded,
          tooltip: '上一首',
          onPressed: state.album == null ? null : () => ref.read(playbackProvider.notifier).prev(),
        ),
        const SizedBox(width: 12),
        _PlayButton(
          playing: state.playing,
          size: widget.compact ? 38 : 32,
          onPressed: state.album == null ? null : () => ref.read(playbackProvider.notifier).toggle(),
        ),
        const SizedBox(width: 12),
        _IconButton(
          icon: Icons.skip_next_rounded,
          tooltip: '下一首',
          onPressed: state.album == null ? null : () => ref.read(playbackProvider.notifier).next(),
        ),
      ],
    );
  }

  // ---- 时间轴 ----
  Widget _buildTimeline(ThemeData theme, double position, double duration) {
    final pct = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        _TimeText(formatTime(position)),
        Expanded(
          child: Slider(
            value: pct,
            onChangeStart: (_) => setState(() => _dragging = true),
            onChanged: (v) => setState(() => _dragValue = v * duration),
            onChangeEnd: (v) {
              setState(() {
                _dragging = false;
                _dragValue = 0;
              });
              ref.read(playbackProvider.notifier).seek(v * duration);
            },
          ),
        ),
        _TimeText(formatTime(duration), right: true),
      ],
    );
  }

  // ---- 播放模式按钮 ----
  Widget _buildModeButton(ThemeData theme, PlaybackState state) {
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        side: WidgetStatePropertyAll(BorderSide(color: theme.dividerColor)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
        elevation: WidgetStatePropertyAll(12),
      ),
      builder: (context, controller, child) => _ModeButton(
        mode: state.mode,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Text('播放模式',
              style: TextStyle(fontSize: 9, letterSpacing: 1, color: theme.hintColor)),
        ),
        for (final m in playModes)
          _ModeOption(
            mode: m,
            active: m.key == state.mode.key,
            onTap: () {
              ref.read(playbackProvider.notifier).setMode(PlaybackModeX.fromKey(m.key));
              ref.read(settingsProvider.notifier).setPlayMode(m.key);
            },
          ),
      ],
    );
  }

  // ---- 音量按钮（纵向弹出滑块与百分比）----
  Widget _buildVolumeButton(ThemeData theme, AppSettings settings) {
    return MenuAnchor(
      alignmentOffset: const Offset(-4, -12),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surface),
        side: WidgetStatePropertyAll(BorderSide(color: theme.dividerColor)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 10, horizontal: 6)),
        elevation: const WidgetStatePropertyAll(12),
      ),
      builder: (context, controller, child) => IconButton(
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        tooltip: '音量',
        iconSize: 18,
        color: theme.hintColor,
        icon: Icon(
          settings.volume == 0
              ? Icons.volume_off_rounded
              : settings.volume < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
        ),
      ),
      menuChildren: [
        SizedBox(
          width: 38,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(settings.volume * 100).round()}%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 110,
                width: 32,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      key: const ValueKey('volume-slider'),
                      value: settings.volume,
                      mouseCursor: SystemMouseCursors.click,
                      onChanged: (v) {
                        ref.read(settingsProvider.notifier).setVolume(v);
                        ref.read(playbackProvider.notifier).setVolume(v);
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  // ---- 桌面置顶歌词按钮 ----
  Widget _buildDesktopLyricsButton(ThemeData theme) {
    final status = ref.watch(desktopLyricsProvider);
    final notifier = ref.read(desktopLyricsProvider.notifier);
    final isShowing = status.isShowing;
    final isLocked = status.isLocked;

    // 组合 Tooltip 提示
    final tooltip = !isShowing
        ? '开启桌面置顶悬浮歌词'
        : isLocked
            ? '桌面歌词已锁定 (点击解锁 / 右键菜单)'
            : '关闭桌面悬浮歌词 (右键可锁定)';

    return MenuAnchor(
      builder: (context, controller, child) => GestureDetector(
        onSecondaryTapDown: (details) {
          if (isShowing) {
            controller.open(position: details.localPosition);
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              onPressed: () async {
                if (isLocked) {
                  // 如果处于锁定状态，点击图标直接解锁
                  await notifier.setLocked(false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已解除桌面歌词鼠标锁定'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } else {
                  final active = await notifier.toggle();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(active ? '已开启桌面置顶悬浮歌词' : '已关闭桌面置顶悬浮歌词'),
                        duration: const Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              tooltip: tooltip,
              iconSize: 18,
              color: isShowing ? theme.colorScheme.primary : theme.hintColor,
              icon: Icon(
                isShowing ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
              ),
            ),
            if (isShowing && isLocked)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 9,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
      menuChildren: [
        MenuItemButton(
          leadingIcon: Icon(
            isLocked ? Icons.lock_open_rounded : Icons.lock_rounded,
            size: 16,
          ),
          onPressed: () async {
            await notifier.setLocked(!isLocked);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(!isLocked ? '已锁定桌面歌词（鼠标点击穿透）' : '已解除桌面歌词锁定'),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: Text(
            isLocked ? '解除悬浮窗锁定' : '锁定悬浮窗（穿透鼠标）',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.close_rounded, size: 16),
          onPressed: () async {
            await notifier.hide();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已关闭桌面悬浮歌词'),
                  duration: Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          child: const Text('关闭桌面歌词', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText(this.text, {this.right = false});

  final String text;
  final bool right;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 37,
      child: Text(
        text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).hintColor,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, this.tooltip, this.onPressed});

  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 20,
      color: onPressed == null ? theme.disabledColor : theme.hintColor,
      icon: Icon(icon),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, this.onPressed, this.size = 32});

  final bool playing;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      mouseCursor: onPressed == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: size * 0.55,
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.mode, required this.onTap});

  final PlaybackMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = playModes.firstWhere((m) => m.key == mode.key);
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(info.label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: theme.hintColor)),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({required this.mode, required this.active, required this.onTap});

  final PlayModeInfo mode;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mode.name,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: active ? theme.colorScheme.primary : theme.colorScheme.onSurface)),
            const SizedBox(height: 2),
            Text(mode.desc, style: TextStyle(fontSize: 9, color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}
