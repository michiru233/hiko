import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../models/album.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_rules.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';

/// 底部播放条：封面 + 标题/艺人 + 控制 + 进度 + 播放模式 + 音量（对应旧版 footer.player）
class PlayerBar extends ConsumerStatefulWidget {
  const PlayerBar({super.key, this.onCoverTap});

  /// 点击当前封面 → 打开详情
  final void Function(Album album)? onCoverTap;

  @override
  ConsumerState<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends ConsumerState<PlayerBar> {
  bool _dragging = false;
  double _dragValue = 0;
  bool _modeOpen = false;
  bool _volumeOpen = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final album = state.album;
    final track = state.currentTrack;

    final position = _dragging ? _dragValue : state.position;
    final duration = state.duration;
    final pct = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
      child: Row(
        children: [
          // 封面
          InkWell(
            onTap: album == null ? null : () => widget.onCoverTap?.call(album),
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              width: 48,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: album == null
                    ? Container(color: const Color(0xFFD5D1E8))
                    : AlbumCover(album: album),
              ),
            ),
          ),
          const SizedBox(width: 15),
          // 元信息
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
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
          ),
          const SizedBox(width: 18),
          // 控制
          Row(
            children: [
              _IconButton(
                icon: '◀◀',
                tooltip: '上一首',
                onPressed: state.album == null ? null : () => ref.read(playbackProvider.notifier).prev(),
              ),
              const SizedBox(width: 14),
              _PlayButton(
                playing: state.playing,
                onPressed: state.album == null ? null : () => ref.read(playbackProvider.notifier).toggle(),
              ),
              const SizedBox(width: 14),
              _IconButton(
                icon: '▶▶',
                tooltip: '下一首',
                onPressed: state.album == null ? null : () => ref.read(playbackProvider.notifier).next(),
              ),
            ],
          ),
          const SizedBox(width: 18),
          // 时间轴
          Expanded(
            child: Row(
              children: [
                _TimeText(formatTime(position)),
                Expanded(
                  child: Slider(
                    value: pct.clamp(0.0, 1.0),
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
            ),
          ),
          // 播放模式
          _Popover(
            open: _modeOpen,
            onClose: () => setState(() => _modeOpen = false),
            button: _ModeButton(
              mode: state.mode,
              onTap: () => setState(() => _modeOpen = !_modeOpen),
            ),
            child: SizedBox(
              width: 236,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                        setState(() => _modeOpen = false);
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 音量
          _Popover(
            open: _volumeOpen,
            onClose: () => setState(() => _volumeOpen = false),
            button: _IconButton(
              icon: settings.volume == 0 ? '◖̸' : (settings.volume < 0.5 ? '◔' : '◖'),
              tooltip: '音量',
              onPressed: () => setState(() => _volumeOpen = !_volumeOpen),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('音量', style: TextStyle(fontSize: 10)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 105,
                  child: Slider(
                    value: settings.volume,
                    onChanged: (v) {
                      ref.read(playbackProvider.notifier).setVolume(v);
                      ref.read(settingsProvider.notifier).setVolume(v);
                    },
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${(settings.volume * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  final String icon;
  final String? tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 12,
      color: onPressed == null ? theme.disabledColor : theme.hintColor,
      icon: Text(icon),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, this.onPressed});

  final bool playing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            playing ? 'Ⅱ' : '▶',
            style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12),
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

class _Popover extends StatelessWidget {
  const _Popover({
    required this.open,
    required this.onClose,
    required this.button,
    required this.child,
  });

  final bool open;
  final VoidCallback onClose;
  final Widget button;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        if (open)
          Positioned(
            right: -10,
            bottom: 38,
            child: GestureDetector(
              onTap: onClose,
              behavior: HitTestBehavior.translucent,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 25, offset: const Offset(0, 10)),
                  ],
                ),
                child: child,
              ),
            ),
          ),
      ],
    );
  }
}
