import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../playback/playback_controller.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../m3e/m3e.dart';

/// 底部播放条（M3EToolbar）：64dp 全圆浮动工具条。
///
/// 两种形态：
/// - **移动端**（`compact: true`，1.99.7 起）：单行 = 封面 40（角 8）+ 标题/艺术家 +
///   上一首/播放/下一首 + 2dp 非交互进度细线（点细线/封面/文字任意处进全屏页）。
/// - **桌面端**（`compact: false`，1.99.59 起三段式）：封面 + 固定的 220dp 标题区 +
///   中间「时间码 · 可拖进度条 · 总时长」（占满剩余宽度，窗口再宽也不留空跑道）+
///   控制键。拖动/点按进度条直接 seek，松手才落位（1.99.59 裁决：三段式方案 B）。
///   点标题区/封面仍然进全屏播放页。
///
/// 播放模式、睡眠定时、倍速、音量、歌词入口全部收进全屏播放页辅助区。
class PlayerBar extends ConsumerStatefulWidget {
  const PlayerBar({
    super.key,
    this.onCoverTap,
    this.compact = false,
    this.onDismiss,
  });

  /// 点击封面 / 元信息 / 进度细线 → 打开全屏播放页
  final void Function(Album album)? onCoverTap;

  /// 移动端紧凑布局（间距收紧）
  final bool compact;

  /// 从左往右划掉播放栏（仅移动端传；为 null 时**不套** [Dismissible]，桌面行为不变）。
  ///
  /// 1.99.6（裁决 Q1=B / Q5=A）：划掉 = 移动端的一种「收起」手势，调用方负责
  /// 藏起本组件并在重新开始播放时还原（见 `home_screen` 的 `_dismissPlayerBar`）。
  final VoidCallback? onDismiss;

  @override
  ConsumerState<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends ConsumerState<PlayerBar> {
  void _openPlayer(Album? album) {
    if (album != null) widget.onCoverTap?.call(album);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final album = state.album;
    final position = state.position;
    final duration = state.duration;
    final pct = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

    final content = RepaintBoundary(
      child: M3EToolbar(
        height: 64,
        margin: widget.compact
            ? const EdgeInsets.fromLTRB(10, 0, 10, 10)
            : const EdgeInsets.all(16),
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 12)
            : const EdgeInsets.symmetric(horizontal: 20),
        child: widget.compact
            ? _compactBody(state, album, pct)
            : _wideBody(state, album, pct),
      ),
    );

    final onDismiss = widget.onDismiss;
    if (onDismiss == null) return content;
    return Dismissible(
      key: const ValueKey('player-bar-dismiss'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.35},
      resizeDuration: null,
      onDismissed: (_) => onDismiss(),
      child: content,
    );
  }

  // ---- 封面 ----
  Widget _buildCover(Album? album) {
    const size = 40.0;
    final cover = SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: M3EShape.radius(M3EShape.sm),
        child: album == null
            ? ColoredBox(color: M3ETheme.of(context).colors.surfaceContainerHighest)
            : AlbumCover(album: album),
      ),
    );
    // 英雄时刻 B 的起点（1.99.29）：桌面端点播放条封面 → 播放页封面连续形变
    if (album == null) return cover;
    return Hero(
      tag: 'bar-cover',
      child: GestureDetector(onTap: () => _openPlayer(album), child: cover),
    );
  }

  // ---- 移动端：单行 + 2dp 非交互细线 ----
  Widget _compactBody(PlaybackState state, Album? album, double pct) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Row(
            children: [
              _buildCover(album),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openPlayer(album),
                  child: _buildMeta(state, album),
                ),
              ),
              const SizedBox(width: 8),
              _buildControls(state),
            ],
          ),
        ),
        const SizedBox(height: 5),
        // 2dp 非交互进度细线：点按进全屏拖动（plan §8.6）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openPlayer(album),
          child: M3EProgress(
            key: const ValueKey('player-bar-progress'),
            value: pct,
            height: 2,
            trackColor:
                M3ETheme.of(context).colors.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  // ---- 桌面端三段式（1.99.59）：封面 + 标题 + 进度（时间码/可拖）+ 控制 ----
  Widget _wideBody(PlaybackState state, Album? album, double pct) {
    return Row(
      children: [
        _buildCover(album),
        const SizedBox(width: 14),
        SizedBox(
          width: 220,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openPlayer(album),
            child: _buildMeta(state, album),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: _buildSeekRow(state, album, pct)),
        const SizedBox(width: 18),
        _buildControls(state),
      ],
    );
  }

  Widget _buildSeekRow(PlaybackState state, Album? album, double pct) {
    final type = M3ETheme.of(context).type;
    final colors = M3ETheme.of(context).colors;
    final style = type.bodySmall.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(
      children: [
        Text(formatTime(state.position), style: style),
        const SizedBox(width: 10),
        Expanded(
          child: _SeekBar(
            key: const ValueKey('player-bar-seek'),
            value: pct,
            enabled: album != null && state.duration > 0,
            onSeek: _seekTo,
          ),
        ),
        const SizedBox(width: 10),
        Text(formatTime(state.duration), style: style),
      ],
    );
  }

  void _seekTo(double fraction) {
    final duration = ref.read(playbackProvider).duration;
    if (duration <= 0) return;
    ref.read(playbackProvider.notifier).seek(fraction * duration);
  }

  // ---- 元信息：标题（含序号）+ 艺术家 · 曲名 ----
  Widget _buildMeta(PlaybackState state, Album? album) {
    final track = state.currentTrack;
    final type = M3ETheme.of(context).type;
    final colors = M3ETheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          album == null
              ? '未在播放'
              : '${album.title} · ${state.queueIndex >= 0 ? (state.queueIndex + 1).toString().padLeft(2, '0') : '01'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.titleSmall.copyWith(color: colors.onSurface),
        ),
        const SizedBox(height: 1),
        Text(
          track == null ? '' : '${album?.artist ?? ''} · ${track.name}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.bodySmall.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  // ---- 播放控制（Material 图标，两端视觉统一；文字符号在部分 Android 字体渲染异常）----
  Widget _buildControls(PlaybackState state) {
    final gap = widget.compact ? 6.0 : 10.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconButton(
          icon: Icons.skip_previous_rounded,
          tooltip: '上一首',
          onPressed: state.album == null
              ? null
              : () => ref.read(playbackProvider.notifier).prev(),
        ),
        SizedBox(width: gap),
        _PlayButton(
          playing: state.playing,
          size: widget.compact ? 38 : 36,
          onPressed: state.album == null
              ? null
              : () => ref.read(playbackProvider.notifier).toggle(),
        ),
        SizedBox(width: gap),
        _IconButton(
          icon: Icons.skip_next_rounded,
          tooltip: '下一首',
          onPressed: state.album == null
              ? null
              : () => ref.read(playbackProvider.notifier).next(),
        ),
      ],
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
      color: onPressed == null ? theme.disabledColor : theme.colorScheme.onSurfaceVariant,
      icon: Icon(icon),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, this.onPressed, this.size = 36});

  final bool playing;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return M3EPressable(
      onTap: onPressed,
      borderRadius: M3EShape.radius(size / 2),
      pressScale: 0.94,
      semanticLabel: playing ? '暂停' : '播放',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: size * 0.55,
            color: colors.onPrimary,
          ),
        ),
      ),
    );
  }
}

/// 三段式播放条里的进度条（1.99.59）：3dp 轨道 + 10dp 圆点。
///
/// 点按与拖动都生效，但**拖动过程只改本地预览**，松手才 seek —— 避免每帧都往
/// 播放器/落盘链路打一次。轨道颜色与 2dp 细线同源（`outlineVariant@0.6`）。
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    super.key,
    required this.value,
    required this.enabled,
    required this.onSeek,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  static const double _thumb = 10;
  double? _drag;

  double _fraction(double dx, double width) {
    if (width <= 0) return 0;
    return (dx / width).clamp(0.0, 1.0);
  }

  void _preview(double dx, double width) {
    if (!widget.enabled) return;
    setState(() => _drag = _fraction(dx, width));
  }

  void _commit() {
    final v = _drag;
    if (v == null) return;
    setState(() => _drag = null);
    widget.onSeek(v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    final value = (_drag ?? widget.value).clamp(0.0, 1.0);
    final enabled = widget.enabled;
    final trackTint = colors.outlineVariant.withValues(
      alpha: enabled ? 0.6 : 0.3,
    );
    final fill = enabled ? colors.primary : colors.outline;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final travel = (width - _thumb).clamp(0.0, double.infinity);
        return Semantics(
          label: '播放进度',
          slider: true,
          value: '${(value * 100).round()}%',
          child: MouseRegion(
            cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown:
                  enabled ? (d) => _preview(d.localPosition.dx, width) : null,
              onTapUp: enabled ? (_) => _commit() : null,
              onHorizontalDragStart:
                  enabled ? (d) => _preview(d.localPosition.dx, width) : null,
              onHorizontalDragUpdate:
                  enabled ? (d) => _preview(d.localPosition.dx, width) : null,
              onHorizontalDragEnd: enabled ? (_) => _commit() : null,
              onHorizontalDragCancel:
                  enabled ? () => setState(() => _drag = null) : null,
              child: SizedBox(
                height: 28,
                child: Center(
                  child: SizedBox(
                    height: _thumb,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: (_thumb - 3) / 2,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: trackTint,
                              borderRadius: M3EShape.radius(M3EShape.full),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: (_thumb - 3) / 2,
                          width: value * width,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: fill,
                              borderRadius: M3EShape.radius(M3EShape.full),
                            ),
                          ),
                        ),
                        Positioned(
                          left: value * travel,
                          top: 0,
                          width: _thumb,
                          height: _thumb,
                          child: Container(
                            decoration: BoxDecoration(
                              color: fill,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
