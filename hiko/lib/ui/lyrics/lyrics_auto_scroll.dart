import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../m3e/m3e.dart';

/// 歌词列表「把当前句滚到歌词区正中」的共用实现。
///
/// 全屏播放页与专辑详情页歌词 tab 各有一份歌词列表，这段定位逻辑曾经被各写一遍：
/// 1.71.0 只改详情页那份、1.71.1 又把详情页 revert 回旧实现改去全屏页，来回误诊两次。
/// 真正的缺陷——目标行还没被 ListView 构建时静默放弃，既没有粗定位也没有重试——
/// 一直留在详情页那份里。共用一份，改一处两处同时生效。
///
/// 1.99.63：粗定位原来按固定估算行高 `index × 45` 硬乘，撞上会换行的长句
/// （DLsite 音声的字幕平均 20–30 字，手机宽度下正好折成 2–3 行，行高 90–140px）
/// 就只能滚到目标的一半以内，目标行仍在构建窗口之外；重试又重算同一个偏移，
/// 三次之后放弃——于是「点开歌词时歌已经播了一会儿」这一最常见路径上，当前句
/// 永远进不了视野，用户看到的是停住不动的旧句子。现在粗定位改成
/// **用已构建行的实测行高做锚点推**，每轮重估，几轮内收敛。
mixin LyricsAutoScroll<T extends StatefulWidget> on State<T> {
  /// 歌词列表的滚动控制器，由宿主视图提供。
  ScrollController get lyricsScrollController;

  /// 每行歌词的 GlobalKey（行索引 → key），由宿主视图的 itemBuilder 填充。
  Map<int, GlobalKey> get lyricsLineKeys;

  /// 目标行尚未构建时的兜底行高（真实行高由锚点推算那步从 Flutter 取）。
  double get lyricsEstimatedLineHeight;

  /// 已经滚过去的高亮行索引，宿主视图用它去重，避免同一行重复滚动。
  int lastRevealedIndex = -1;

  bool _autoScrollEnabled = true;

  /// 粗定位最多连做几轮。每轮都用实测行高重估，所以正常两轮内就能把目标行
  /// 带进构建窗口；给到 5 轮是给「一屏里既有单行也有五行」这种极端混排留余量。
  static const int _maxRevealAttempts = 5;

  /// 超过一屏半的距离直接跳，不做动画：飞越几十行的长动画看不清内容，还会被
  /// 下一句的定位打断，观感上就是「一直在滚却总不对」。
  static const double _smoothRevealViewports = 1.5;

  /// 把第 [index] 行滚到歌词区垂直正中。
  ///
  /// 目标行的 GlobalKey 只在 itemBuilder 里才建立，所以跨行远跳（拖动进度条、
  /// 点远处某句、点开歌词时歌已播到中段）时它往往还没被构建。这时先按实测行高
  /// 粗跳一次把它带进构建范围，下一帧再精确对齐；限次防死循环。
  ///
  /// `alignment: 0.5` 的参照系是 viewport 自身高度（`viewportDimension`），
  /// 即歌词区中心，而不是整个屏幕中心。
  void revealLyricsLine(int index, {int attempt = 0}) {
    if (index < 0 || !mounted) return;

    if (!lyricsScrollController.hasClients) {
      // 列表还没挂上（首帧或视图刚切过来），下一帧再试，别静默放弃。
      _retryReveal(index, attempt);
      return;
    }

    final position = lyricsScrollController.position;
    final renderObject = _renderObjectOf(index);
    final viewport =
        renderObject == null ? null : RenderAbstractViewport.maybeOf(renderObject);

    if (viewport == null) {
      if (attempt >= _maxRevealAttempts) return;
      final estimate = _estimateOffsetFor(index, position);
      if (estimate == null) return;
      lyricsScrollController.jumpTo(estimate);
      _retryReveal(index, attempt);
      return;
    }

    final target = viewport
        .getOffsetToReveal(renderObject!, 0.5)
        .offset
        .clamp(0.0, position.maxScrollExtent);

    final travel = (target - position.pixels).abs();
    if (travel < 1) return;

    if (attempt > 0 || travel > position.viewportDimension * _smoothRevealViewports) {
      // 远距离落点、或这是粗定位之后的重估轮：直接跳，再验一轮。
      // 不能在这里接动画——上一跳的动画还没跑完就再起一段，两段落点会互相
      // 打断，最终停在中间（抽屉视图实测残留 148px）。
      lyricsScrollController.jumpTo(target);
      if (attempt < _maxRevealAttempts) _retryReveal(index, attempt);
      return;
    }

    final motion = M3ETheme.of(context).motion;
    lyricsScrollController.animateTo(
      target,
      duration: motion.duration(M3ESpringType.spatial, M3ESpringSpeed.normal),
      curve: motion.fallbackCurve,
    );
  }

  /// 同步「自动跟随」开关，并在刚恢复跟随时清掉去重记账。
  ///
  /// 手动滚动会把 `autoScrollEnabled` 置 false，3 秒后自动恢复；恢复那一刻
  /// 当前句可能已经换了一两句、而列表停在用户手指留下的位置。旧实现只把开关
  /// 翻回 true，不等下一句变化就不会再定位，用户看到的就是「跟随断了、得自己
  /// 滑回来」。清掉 `lastRevealedIndex` 让宿主视图下一次 build 立刻重新居中。
  void syncAutoScrollState(bool enabled) {
    if (enabled && !_autoScrollEnabled) {
      // 「回到当前句」按钮会先自己滚（recenterNow），这时不要再排一次队；
      // 只有计时器自动恢复这种没人管的场景才需要靠 build 补一次回中。
      if (_pendingRecenter == null) lastRevealedIndex = -1;
      _pendingRecenter = null;
    }
    _autoScrollEnabled = enabled;
  }

  /// 用户主动点「回到当前句」：立刻定位，不等下一帧 build。
  ///
  /// 走 build 那条路要多等一帧（状态变更 → 重建 → post-frame 回调 → 起动画），
  /// 落位观感明显滞后；这里同步起动画，并把去重记账写成目标行，避免同帧再滚一次。
  void recenterNow(int index) {
    _pendingRecenter = index;
    lastRevealedIndex = index;
    revealLyricsLine(index);
  }

  int? _pendingRecenter;

  void _retryReveal(int index, int attempt) {
    if (attempt >= _maxRevealAttempts) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) revealLyricsLine(index, attempt: attempt + 1);
    });
  }

  RenderObject? _renderObjectOf(int index) {
    final renderObject = lyricsLineKeys[index]?.currentContext?.findRenderObject();
    if (renderObject == null || !renderObject.attached) return null;
    return renderObject;
  }

  /// 某个已构建行在滚动坐标系里的偏移（[alignment] 为 0 对齐视口顶端、0.5 居中）。
  double? _lineOffset(RenderObject renderObject, {double alignment = 0.5}) {
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    return viewport?.getOffsetToReveal(renderObject, alignment).offset;
  }

  /// 用已构建行实测出来的平均行高。
  ///
  /// 取「最上」和「最下」两个已构建行求斜率，比逐行平均更稳（不受个别超高行影响）。
  /// 少于 3 个采样点时返回 null，交回兜底估算——两个点的斜率误差会被目标距离放大。
  double? _measuredLineHeight() {
    final samples = <MapEntry<int, double>>[];
    for (final entry in lyricsLineKeys.entries) {
      final renderObject = _renderObjectOf(entry.key);
      if (renderObject == null) continue;
      final offset = _lineOffset(renderObject);
      if (offset == null) continue;
      samples.add(MapEntry(entry.key, offset));
    }
    if (samples.length < 3) return null;
    samples.sort((a, b) => a.key.compareTo(b.key));
    final first = samples.first;
    final last = samples.last;
    final span = last.key - first.key;
    if (span <= 0) return null;
    final height = (last.value - first.value) / span;
    // 实测值明显不合理时宁可不用（例如行被折叠成 0 高）
    return height.isFinite && height > 8 ? height : null;
  }

  /// 目标行还没构建时的落点估算：优先「最近已构建行 + 实测行高 × 索引差」。
  double? _estimateOffsetFor(int index, ScrollPosition position) {
    MapEntry<int, double>? anchor;
    var bestGap = 1 << 30;
    for (final entry in lyricsLineKeys.entries) {
      final renderObject = _renderObjectOf(entry.key);
      if (renderObject == null) continue;
      final offset = _lineOffset(renderObject);
      if (offset == null) continue;
      final gap = (entry.key - index).abs();
      if (gap < bestGap) {
        bestGap = gap;
        anchor = MapEntry(entry.key, offset);
      }
    }

    final perLine = _measuredLineHeight() ?? lyricsEstimatedLineHeight;
    final estimated = anchor == null
        ? index * perLine
        : anchor.value + (index - anchor.key) * perLine;
    if (!estimated.isFinite) return null;
    return estimated.clamp(0.0, position.maxScrollExtent);
  }

  /// 给歌词列表用的上下留白：各留半个可视高度，首句与末句才能也滚到正中。
  ///
  /// 不留余量时列表最前面/最后面约 3 句永远差 59–145px 到不了正中——滚动位置
  /// 被 `clamp` 夹在 `0` 与 `maxScrollExtent` 上，物理上没有空间可滚。
  /// 返回 0 表示宿主视图尺寸还没量出来，此时按 0 处理即可。
  double lyricsCenterSlack(double viewportHeight) =>
      viewportHeight.isFinite ? viewportHeight / 2 : 0.0;
}
