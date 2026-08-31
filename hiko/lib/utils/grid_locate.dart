import '../models/album.dart';

/// 网格定位纯函数（1.49）：「定位当前播放」按钮用。
/// 计算「正在播放专辑卡」在专辑网格中的索引、列数与目标行滚动偏移，
/// 供 HomeScreen 大库（数万张、懒加载）下直接 jumpTo，不依赖逐卡构建。
/// 纯 Dart 不依赖 Flutter，公式与 SliverGridDelegate 两种实现保持一致：
/// 列数（MaxExtent 型）＝ max(1, ceil(crossExtent / (maxExtent + spacing)))，
/// 卡宽＝ (crossExtent − spacing×(列−1)) / 列，卡高＝ 卡宽 / childAspectRatio。
/// scrollOffset 为「目标行在滚动内容中的起始位置」（含 GridView 顶部 padding），
/// 可能超出最大可滚范围，由调用方 clamp 到 maxScrollExtent。

/// 网格布局参数（与 `_buildGrid` 的 GridView 设置一一对应）
class GridMetrics {
  /// true＝SliverGridDelegateWithFixedCrossAxisCount（设置指定每行专辑数）；
  /// false＝SliverGridDelegateWithMaxCrossAxisExtent（按视口宽自适应）
  final bool useFixedCount;

  /// useFixedCount=true 时生效（<1 按 1 处理）
  final int fixedCrossAxisCount;

  /// useFixedCount=false 时生效：单卡最大宽
  final double maxCrossAxisExtent;

  final double crossAxisSpacing;
  final double mainAxisSpacing;

  /// 卡宽/卡高
  final double childAspectRatio;

  /// GridView 视口总宽（含左右 padding）
  final double viewportWidth;

  /// 左右 padding 之和（桌面 48+48，移动 16+16）
  final double horizontalPadding;

  /// 顶部 padding（16）
  final double topPadding;

  const GridMetrics({
    required this.useFixedCount,
    this.fixedCrossAxisCount = 1,
    this.maxCrossAxisExtent = 190,
    this.crossAxisSpacing = 18,
    this.mainAxisSpacing = 25,
    this.childAspectRatio = 0.60,
    required this.viewportWidth,
    this.horizontalPadding = 0,
    this.topPadding = 0,
  });
}

/// 定位结果
class GridLocateResult {
  /// 目标是否在列表中
  final bool found;

  /// 目标索引；未找到为 -1
  final int index;

  /// 实际列数
  final int columns;

  /// 目标行起始滚动偏移；未找到为 0
  final double scrollOffset;

  const GridLocateResult({
    required this.found,
    required this.index,
    required this.columns,
    required this.scrollOffset,
  });
}

/// 在专辑网格中定位 [albumId]，算出目标行滚动偏移。
GridLocateResult locateAlbumInGrid({
  required List<Album> filtered,
  required String? albumId,
  required GridMetrics metrics,
}) {
  final crossExtent =
      (metrics.viewportWidth - metrics.horizontalPadding).clamp(0.0, double.infinity);
  final int columns;
  if (metrics.useFixedCount) {
    columns = metrics.fixedCrossAxisCount < 1 ? 1 : metrics.fixedCrossAxisCount;
  } else {
    // 与 SDK 一致用 ceil（保证卡宽 ≤ maxCrossAxisExtent），至少 1 列
    columns = crossExtent <= 0
        ? 1
        : (crossExtent / (metrics.maxCrossAxisExtent + metrics.crossAxisSpacing))
            .ceil()
            .clamp(1, 1 << 30);
  }
  final tileWidth = (crossExtent - (columns - 1) * metrics.crossAxisSpacing) / columns;
  final tileHeight =
      metrics.childAspectRatio > 0 ? tileWidth / metrics.childAspectRatio : 0.0;

  final index = filtered.indexWhere((a) => a.id == albumId);
  if (index < 0) {
    return GridLocateResult(found: false, index: -1, columns: columns, scrollOffset: 0);
  }
  final row = index ~/ columns;
  final offset =
      metrics.topPadding + row * (tileHeight + metrics.mainAxisSpacing);
  return GridLocateResult(found: true, index: index, columns: columns, scrollOffset: offset);
}
