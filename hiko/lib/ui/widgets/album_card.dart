import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../theme.dart';

/// 专辑卡片：玻璃拟态质感卡片（双层微反光边缘 + 柔和投光 + 胶囊标签）
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
    final isDark = theme.brightness == Brightness.dark;
    Offset? pointerPosition;

    // 玻璃卡片表面：长列表滚动使用高性能 Faux-Glass（高透半透明 + 渐变微反光）
    final cardBg = isDark ? HikoColors.darkGlassCard : HikoColors.lightGlassCard;
    final cardBorder = isDark ? HikoColors.darkGlassBorderSubtle : HikoColors.lightGlassBorderSubtle;

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
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: highlighted || selected
                    ? Border.all(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      )
                    : null,
                boxShadow: [
                  if (highlighted)
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: 2,
                    )
                  else
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: AlbumCover(album: album),
                            ),
                          ),
                          if (multiMode)
                            Positioned(
                              left: 8,
                              top: 8,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: onTap,
                                    customBorder: const CircleBorder(),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: selected
                                            ? theme.colorScheme.primary
                                            : Colors.black.withValues(alpha: 0.45),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.9),
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
                        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              album.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 5,
                              runSpacing: 4,
                              children: [
                                _Pill(
                                  text: album.artist,
                                  bg: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.05),
                                  color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
                                  maxWidth: contentWidth,
                                ),
                                if (album.albumArtist.isNotEmpty &&
                                    album.albumArtist != album.artist)
                                  _Pill(
                                    text: album.albumArtist,
                                    bg: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.05),
                                    color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
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
                                  bg: theme.colorScheme.primary.withValues(alpha: 0.9),
                                  color: theme.colorScheme.onPrimary,
                                  bold: true,
                                  maxWidth: contentWidth,
                                ),
                                _Pill(
                                  text: album.totalDuration > 0
                                      ? formatDuration(album.totalDuration)
                                      : '${album.duration} 首',
                                  bg: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.04),
                                  color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                                  maxWidth: contentWidth,
                                ),
                                if (album.genre.isNotEmpty)
                                  _Tag(text: album.genre, maxWidth: contentWidth),
                              ],
                            ),
                            if (showScrapedTags && album.tags.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 5,
                                runSpacing: 4,
                                children: [
                                  for (final tag in album.tags.take(3))
                                    _Tag(
                                      text: tag,
                                      color: const Color(0xFF2E8A8F),
                                      bg: const Color(0xFFE3F4F2).withValues(alpha: isDark ? 0.2 : 0.8),
                                      maxWidth: contentWidth,
                                    ),
                                  if (album.tags.length > 3)
                                    _Tag(
                                      text: '+${album.tags.length - 3}',
                                      color: const Color(0xFF2E8A8F),
                                      bg: const Color(0xFFD7ECEA).withValues(alpha: isDark ? 0.2 : 0.8),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
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
    final isDark = theme.brightness == Brightness.dark;
    Widget tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        softWrap: true,
        style: TextStyle(fontSize: 9, color: color ?? (isDark ? HikoColors.darkMuted : HikoColors.lightMuted)),
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
