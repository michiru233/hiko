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
    return LayoutBuilder(
      builder: (context, constraints) {
        // 1.99.61：横向边距原来写死 48 —— 360dp 手机上三张卡只剩 264dp，
        // 「累计收听」的「12小时34分钟」在 titleMedium 下会挤爆。窄屏收到 16，
        // 同时把三张卡从固定 Row 换成竖排。
        final wide = constraints.maxWidth >= 720;
        final horizontal = wide ? 48.0 : 16.0;
        final cards = <Widget>[
          _statCard(
            theme,
            label: '累计收听',
            value: formatDuration(stats.totalListenSeconds),
            icon: Icons.headphones_rounded,
          ),
          _statCard(
            theme,
            label: '专辑总数',
            value: '${stats.albumCount}',
            icon: Icons.library_music_rounded,
          ),
          _statCard(
            theme,
            label: '已评分',
            value: '${stats.ratedCount}',
            icon: Icons.star_rounded,
          ),
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 32),
          children: [
            Text('统计', style: M3ETheme.of(context).type.headlineSmall.copyWith(color: theme.colorScheme.onSurface)),
            const SizedBox(height: 16),
            if (wide)
              Row(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: cards[i]),
                  ],
                ],
              )
            else
              Column(
                children: [
                  for (int i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    cards[i],
                  ],
                ],
              ),
            const SizedBox(height: 12),
            // 三颗状态 chip 原来也是固定 Row：窄屏 + 大字号时会溢出，改 Wrap。
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(theme, '听完 ${stats.finishedCount}', M3ESemantic.statFinished),
                _chip(theme, '听过 ${stats.startedCount}', M3ESemantic.statStarted),
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
      },
    );
  }

  /// 三张统计卡之一。**不再自带 `Expanded`** —— 宽屏由调用点包 `Expanded`、
  /// 窄屏放进 `Column`，同一个 widget 两种布局都成立。
  Widget _statCard(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return M3ECard(
      padding: const EdgeInsets.all(14),
      radius: M3EShape.lg,
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const M3EType().titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const M3EType().labelSmall.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
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
