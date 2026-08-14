import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';

/// 专辑卡片（对应旧版 .album-card）：封面 + 悬停操作 + 标题/艺人 + 标签
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.multiMode,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
  });

  final Album album;
  final bool multiMode;
  final bool selected;
  final VoidCallback onTap;

  /// 右键（桌面）/长按（移动）菜单回调，携带触发位置
  final void Function(Offset position)? onContextMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 桌面端悬停显示点击指针（GestureDetector 默认不切换光标）
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onLongPressStart: onContextMenu == null
            ? null
            : (d) => onContextMenu!(d.globalPosition),
        onSecondaryTapDown: onContextMenu == null
            ? null
            : (d) => onContextMenu!(d.globalPosition),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面 + 多选勾选（固定正方形，占卡片上部）
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: AlbumCover(album: album),
                      ),
                    ),
                    if (multiMode)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: onTap,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : Colors.black.withValues(alpha: 0.4),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  selected ? '✓' : '',
                                  style: TextStyle(
                                    color: selected
                                        ? theme.colorScheme.onPrimary
                                        : Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (selected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: theme.colorScheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            // 信息区：占封面下方剩余空间（高度由网格宽高比决定，杜绝溢出）
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            album.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (album.albumArtist.isNotEmpty)
                          Flexible(
                            child: Text(
                              '· ${album.albumArtist}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10, color: theme.hintColor),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${album.artist} · ${album.rjCode ?? '本地导入'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _Tag(
                          text: album.genre,
                          color: theme.colorScheme.primary,
                          bg: theme.colorScheme.primaryContainer,
                        ),
                        const SizedBox(width: 5),
                        _Tag(
                          text: album.totalDuration > 0
                              ? formatDuration(album.totalDuration)
                              : '${album.duration} 首',
                        ),
                      ],
                    ),
                    if (album.tags.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final t in album.tags.take(3))
                            _Tag(
                              text: t,
                              color: const Color(0xFF2E8A8F),
                              bg: const Color(0xFFE3F4F2),
                            ),
                          if (album.tags.length > 3)
                            _Tag(
                              text: '+${album.tags.length - 3}',
                              color: const Color(0xFF2E8A8F),
                              bg: const Color(0xFFD7ECEA),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color, this.bg});

  final String text;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, color: color ?? theme.hintColor),
      ),
    );
  }
}
