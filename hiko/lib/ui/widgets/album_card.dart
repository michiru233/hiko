import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';

/// 专辑卡片：封面 + 悬停操作 + 标题/艺人 + 标签。
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.multiMode,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
    this.showScrapedTags = false,
    this.highlighted = false,
  });

  final Album album;
  final bool multiMode;
  final bool selected;
  final VoidCallback onTap;
  final void Function(Offset position)? onContextMenu;
  final bool showScrapedTags;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Offset? pointerPosition;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (event) {
          pointerPosition = event.position;
          if (onContextMenu != null && event.buttons == kSecondaryButton) {
            onContextMenu!(event.position);
          }
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onContextMenu == null
                ? null
                : () => onContextMenu!(pointerPosition ?? Offset.zero),
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: highlighted
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.45,
                          ),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    )
                  : const BoxDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: onTap,
                                    customBorder: const CircleBorder(),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: selected
                                            ? theme.colorScheme.primary
                                            : Colors.black.withValues(
                                                alpha: 0.4,
                                              ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.85,
                                          ),
                                          width: 2,
                                        ),
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
                            ),
                          if (selected)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: theme.colorScheme.primary,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final contentWidth = (constraints.maxWidth - 4).clamp(
                        1.0,
                        double.infinity,
                      );
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                _Pill(
                                  text: album.artist,
                                  bg: theme.colorScheme.secondaryContainer,
                                  color: theme.colorScheme.onSecondaryContainer,
                                  maxWidth: contentWidth,
                                ),
                                if (album.albumArtist.isNotEmpty &&
                                    album.albumArtist != album.artist)
                                  _Pill(
                                    text: album.albumArtist,
                                    bg: theme.colorScheme.secondaryContainer,
                                    color:
                                        theme.colorScheme.onSecondaryContainer,
                                    maxWidth: contentWidth,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                _Pill(
                                  text: album.rjCode ?? '本地导入',
                                  bg: theme.colorScheme.primary,
                                  color: theme.colorScheme.onPrimary,
                                  bold: true,
                                  maxWidth: contentWidth,
                                ),
                                _Pill(
                                  text: album.totalDuration > 0
                                      ? formatDuration(album.totalDuration)
                                      : '${album.duration} 首',
                                  bg: theme.colorScheme.secondaryContainer,
                                  color: theme.colorScheme.onSecondaryContainer,
                                  maxWidth: contentWidth,
                                ),
                                _Tag(text: album.genre, maxWidth: contentWidth),
                              ],
                            ),
                            if (showScrapedTags && album.tags.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [
                                  for (final tag in album.tags.take(3))
                                    _Tag(
                                      text: tag,
                                      color: const Color(0xFF2E8A8F),
                                      bg: const Color(0xFFE3F4F2),
                                      maxWidth: contentWidth,
                                    ),
                                  if (album.tags.length > 3)
                                    _Tag(
                                      text: '+${album.tags.length - 3}',
                                      color: const Color(0xFF2E8A8F),
                                      bg: const Color(0xFFD7ECEA),
                                      maxWidth: contentWidth,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 元数据胶囊：文本在卡片内自然换行，不截断单个字段。
class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.bg,
    required this.color,
    this.bold = false,
    this.maxWidth,
  });

  final String text;
  final Color bg;
  final Color color;
  final bool bold;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        softWrap: true,
        style: TextStyle(
          fontSize: 10,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: color,
        ),
      ),
    );
    if (maxWidth != null) {
      pill = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: pill,
      );
    }
    return pill;
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color, this.bg, this.maxWidth});

  final String text;
  final Color? color;
  final Color? bg;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        softWrap: true,
        style: TextStyle(fontSize: 9, color: color ?? theme.hintColor),
      ),
    );
    if (maxWidth != null) {
      tag = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: tag,
      );
    }
    return tag;
  }
}
