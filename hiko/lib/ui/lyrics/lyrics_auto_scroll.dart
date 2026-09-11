import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 歌词列表「把当前句滚到歌词区正中」的共用实现。
///
/// 全屏播放页与专辑详情页歌词 tab 各有一份歌词列表，这段定位逻辑曾经被各写一遍：
/// 1.71.0 只改详情页那份、1.71.1 又把详情页 revert 回旧实现改去全屏页，来回误诊两次。
/// 真正的缺陷——目标行还没被 ListView 构建时静默放弃，既没有粗定位也没有重试——
/// 一直留在详情页那份里。共用一份，改一处两处同时生效。
mixin LyricsAutoScroll<T extends StatefulWidget> on State<T> {
  /// 歌词列表的滚动控制器，由宿主视图提供。
  ScrollController get lyricsScrollController;

  /// 每行歌词的 GlobalKey（行索引 → key），由宿主视图的 itemBuilder 填充。
  Map<int, GlobalKey> get lyricsLineKeys;

  /// 目标行尚未构建时用的估算行高（真实行高由精确对齐那步从 Flutter 取）。
  double get lyricsEstimatedLineHeight;

  /// 已经滚过去的高亮行索引，宿主视图用它去重，避免同一行重复滚动。
  int lastRevealedIndex = -1;

  /// 把第 [index] 行滚到歌词区垂直正中。
  ///
  /// 目标行的 GlobalKey 只在 itemBuilder 里才建立，所以跨行远跳（拖动进度条、
  /// 点远处某句）时它往往还没被构建。这时先按估算行高粗跳一次把它带进构建范围，
  /// 下一帧再精确对齐；限次防死循环。
  ///
  /// `alignment: 0.5` 的参照系是 viewport 自身高度（`viewportDimension`），
  /// 即歌词区中心，而不是整个屏幕中心。
  void revealLyricsLine(int index, {int attempt = 0}) {
    if (index < 0 || !mounted) return;

    if (!lyricsScrollController.hasClients) {
      // 列表还没挂上（首帧或视图刚切过来），下一帧再试，别静默放弃。
      _retryNextFrame(index, attempt);
      return;
    }

    final position = lyricsScrollController.position;
    final renderObject = lyricsLineKeys[index]?.currentContext?.findRenderObject();
    final viewport =
        renderObject == null ? null : RenderAbstractViewport.maybeOf(renderObject);

    if (viewport == null) {
      if (attempt >= 2) return;
      lyricsScrollController.jumpTo(
        (index * lyricsEstimatedLineHeight).clamp(0.0, position.maxScrollExtent),
      );
      _retryNextFrame(index, attempt);
      return;
    }

    final target = viewport
        .getOffsetToReveal(renderObject!, 0.5)
        .offset
        .clamp(0.0, position.maxScrollExtent);

    lyricsScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _retryNextFrame(int index, int attempt) {
    if (attempt >= 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) revealLyricsLine(index, attempt: attempt + 1);
    });
  }

  /// 给歌词列表用的上下留白：各留半个可视高度，首句与末句才能也滚到正中。
  ///
  /// 不留余量时列表最前面/最后面约 3 句永远差 59–145px 到不了正中——滚动位置
  /// 被 `clamp` 夹在 `0` 与 `maxScrollExtent` 上，物理上没有空间可滚。
  /// 返回 0 表示宿主视图尺寸还没量出来，此时按 0 处理即可。
  double lyricsCenterSlack(double viewportHeight) =>
      viewportHeight.isFinite ? viewportHeight / 2 : 0.0;
}
