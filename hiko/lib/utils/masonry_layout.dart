import '../models/album.dart';

/// A lightweight estimate of the layout produced by SliverMasonryGrid.
/// It is used only to get close enough for a lazy grid jump; ensureVisible
/// performs the final correction once the target child has been built.
class MasonryLayoutMetrics {
  const MasonryLayoutMetrics({
    required this.viewportWidth,
    this.horizontalPadding = 0,
    this.crossAxisSpacing = 18,
    this.mainAxisSpacing = 25,
    this.maxCrossAxisExtent = 260,
    this.fixedCrossAxisCount,
    this.showScrapedTags = false,
  });

  final double viewportWidth;
  final double horizontalPadding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double maxCrossAxisExtent;
  final int? fixedCrossAxisCount;
  final bool showScrapedTags;
}

class MasonryLocateResult {
  const MasonryLocateResult({
    required this.found,
    required this.index,
    required this.column,
    required this.scrollOffset,
  });

  final bool found;
  final int index;
  final int column;
  final double scrollOffset;
}

int masonryColumnCount(MasonryLayoutMetrics metrics) {
  final crossExtent = (metrics.viewportWidth - metrics.horizontalPadding).clamp(
    0.0,
    double.infinity,
  );
  if (metrics.fixedCrossAxisCount != null) {
    return metrics.fixedCrossAxisCount!.clamp(1, 1 << 30);
  }
  if (crossExtent <= 0 || metrics.maxCrossAxisExtent <= 0) return 1;
  return (crossExtent / (metrics.maxCrossAxisExtent + metrics.crossAxisSpacing))
      .ceil()
      .clamp(1, 1 << 30);
}

/// Estimates item placement using the same shortest-column rule as the
/// package's masonry render object. Text measurements are deliberately
/// conservative so the jump lands before the target rather than past it.
MasonryLocateResult locateAlbumInMasonry({
  required List<Album> albums,
  required String? albumId,
  required MasonryLayoutMetrics metrics,
}) {
  final index = albums.indexWhere((album) => album.id == albumId);
  final columns = masonryColumnCount(metrics);
  if (index < 0) {
    return const MasonryLocateResult(
      found: false,
      index: -1,
      column: -1,
      scrollOffset: 0,
    );
  }

  final crossExtent = (metrics.viewportWidth - metrics.horizontalPadding).clamp(
    0.0,
    double.infinity,
  );
  final tileWidth = columns == 0
      ? 0.0
      : (crossExtent - (columns - 1) * metrics.crossAxisSpacing) / columns;
  final offsets = List<double>.filled(columns, 0);
  var targetColumn = 0;
  var targetOffset = 0.0;

  for (var i = 0; i <= index; i++) {
    targetColumn = _shortestColumn(offsets);
    targetOffset = offsets[targetColumn];
    offsets[targetColumn] =
        targetOffset +
        estimateAlbumCardHeight(albums[i], tileWidth, metrics.showScrapedTags) +
        metrics.mainAxisSpacing;
  }

  return MasonryLocateResult(
    found: true,
    index: index,
    column: targetColumn,
    scrollOffset: targetOffset,
  );
}

int _shortestColumn(List<double> offsets) {
  var shortest = 0;
  for (var i = 1; i < offsets.length; i++) {
    if (offsets[i] < offsets[shortest]) shortest = i;
  }
  return shortest;
}

/// Approximate natural card height. The estimate intentionally overstates
/// wrapped text by a small amount to keep lazy targets reachable.
double estimateAlbumCardHeight(
  Album album,
  double width,
  bool showScrapedTags,
) {
  if (width <= 0) return 0;
  final innerWidth = (width - 4).clamp(1.0, double.infinity);
  final titleLines = _wrappedLines(album.title, innerWidth, 13, maxLines: 4);
  final artistLines = _wrapPills([
    album.artist,
    if (album.albumArtist.isNotEmpty && album.albumArtist != album.artist)
      album.albumArtist,
  ], innerWidth);
  final detailLines = _wrapPills([
    album.rjCode ?? '本地导入',
    album.totalDuration > 0
        ? _durationLabel(album.totalDuration)
        : '${album.duration} 首',
    album.genre,
  ], innerWidth);
  final tagLines = showScrapedTags && album.tags.isNotEmpty
      ? _wrapPills([
          ...album.tags.take(3),
          if (album.tags.length > 3) '+${album.tags.length - 3}',
        ], innerWidth)
      : 0;

  var infoHeight = 8 + titleLines * 16.0 + 4;
  infoHeight += artistLines * 22.0 + 6;
  infoHeight += detailLines * 22.0;
  if (tagLines > 0) infoHeight += 5 + tagLines * 22.0;
  return width + infoHeight + 2;
}

int _wrappedLines(
  String text,
  double width,
  double fontSize, {
  required int maxLines,
}) {
  final charsPerLine = (width / (fontSize * 0.58)).floor().clamp(1, 1000);
  return (text.length / charsPerLine).ceil().clamp(1, maxLines);
}

int _wrapPills(List<String> texts, double width) {
  if (texts.isEmpty) return 0;
  var rows = 1;
  var used = 0.0;
  for (final text in texts) {
    final pillWidth = (text.length * 6.0 + 12).clamp(20.0, width);
    if (used > 0 && used + 5 + pillWidth > width) {
      rows++;
      used = pillWidth;
    } else {
      used += (used == 0 ? 0 : 5) + pillWidth;
    }
  }
  return rows;
}

String _durationLabel(double seconds) {
  final totalSeconds = seconds.round();
  final minutes = totalSeconds ~/ 60;
  final remainder = totalSeconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}
