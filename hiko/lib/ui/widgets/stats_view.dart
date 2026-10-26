import 'package:flutter/material.dart';

import '../../data/stats.dart';
import '../../models/album.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../m3e/m3e.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// 统计视图（1.48）：总收听时长 / 听完·听过·未听 / 最近播放 Top 20
class StatsView extends StatelessWidget {
  const StatsView({
    super.key,
    required this.stats,
    required this.onOpenAlbum,
  });

  final LibraryStats stats;
  final ValueChanged<Album> onOpenAlbum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(48, 20, 48, 32),
      children: [
        Text('统计', style: M3ETheme.of(context).type.headlineSmall.copyWith(color: theme.colorScheme.onSurface)),
        const SizedBox(height: 16),
        Row(
          children: [
            _statCard(
              theme,
              label: '累计收听',
              value: formatDuration(stats.totalListenSeconds),
              icon: Icons.headphones_rounded,
            ),
            const SizedBox(width: 12),
            _statCard(
              theme,
              label: '专辑总数',
              value: '${stats.albumCount}',
              icon: Icons.library_music_rounded,
            ),
            const SizedBox(width: 12),
            _statCard(
              theme,
              label: '已评分',
              value: '${stats.ratedCount}',
              icon: Icons.star_rounded,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _chip(theme, '听完 ${stats.finishedCount}', M3ESemantic.statFinished),
            const SizedBox(width: 8),
            _chip(theme, '听过 ${stats.startedCount}', M3ESemantic.statStarted),
            const SizedBox(width: 8),
            _chip(theme, '未听 ${stats.unplayedCount}', M3ESemantic.statUnplayed),
          ],
        ),
        const SizedBox(height: 24),
        Text('最近播放', style: const M3EType().titleSmall.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        )),
        const SizedBox(height: 8),
        if (stats.recentlyPlayed.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              '还没有播放记录',
              style: const M3EType().bodySmall.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...stats.recentlyPlayed.map((a) => _recentRow(context, theme, a)),
      ],
    );
  }

  Widget _statCard(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: M3ECard(
        padding: const EdgeInsets.all(14),
        radius: M3EShape.lg,
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const M3EType().titleMedium.copyWith(
                  fontWeight: FontWeight.w700,
                )),
                Text(label, style: const M3EType().labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: M3EShape.radius(M3EShape.lgPlus),
      ),
      child: Text(label, style: const M3EType().labelSmall.copyWith(
        fontWeight: FontWeight.w600,
        color: color,
      )),
    );
  }

  Widget _recentRow(BuildContext context, ThemeData theme, Album album) {
    final playedAt = album.lastPlayedAt;
    final dateText = playedAt != null
        ? '${_two(playedAt.month)}-${_two(playedAt.day)} ${_two(playedAt.hour)}:${_two(playedAt.minute)}'
        : '';
    return InkWell(
      onTap: () => onOpenAlbum(album),
      borderRadius: M3EShape.radius(M3EShape.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: ClipRRect(
                borderRadius: M3EShape.radius(M3EShape.sm),
                child: AlbumCover(album: album),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                album.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const M3EType().bodyMedium.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              album.rating > 0 ? '★' * album.rating : '',
              style: const M3EType().labelSmall.copyWith(color: M3ESemantic.rating),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: Text(
                dateText,
                style: const M3EType().labelSmall.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
