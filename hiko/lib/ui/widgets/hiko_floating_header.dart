import 'package:flutter/material.dart';

/// 移动端可滚动页面顶部的「浮层玻璃头部」。
///
/// 三个页面（本地音声 / 在线浏览 / 在线收藏）的头部是同一份结构：
/// 零高 toolbar + 整块自定义头部挂成 `SliverAppBar.bottom`，再配一张
/// 离屏副本量出来的自然高度当 extent。它们的差异只有 [extent] 和内容，
/// 参数则必须逐字一致 —— 尤其是下面这个 `preferredSize` 的坑，
/// 所以收在一个类里，别让三处各改各的。
///
/// 用法：
/// ```dart
/// CustomScrollView(
///   controller: _gridScrollController,
///   slivers: [
///     HikoFloatingGlassHeader(
///       extent: _localHeaderExtent ?? 300,
///       child: headerColumn,
///     ),
///     ...
///   ],
/// )
/// ```
class HikoFloatingGlassHeader extends StatelessWidget {
  const HikoFloatingGlassHeader({
    super.key,
    required this.extent,
    required this.child,
  });

  /// 头部自然高度（调用方用离屏副本量出来）。
  final double extent;

  /// 头部内容，通常是一摞 `HikoGlass` 卡片。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      primary: false,
      automaticallyImplyLeading: false,
      pinned: false,
      floating: true,
      // snap 会以 layoutExtent=0 覆盖内容（1.99.7 实测踩坑，见在线页记录），
      // floating 本身就有「上滑跟着手指即时滑回」的 reveal 行为，够用
      snap: false,
      toolbarHeight: 0,
      // 真实高度只能从这里表达，见 `bottom` 上的长注释
      expandedHeight: extent,
      collapsedHeight: extent,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      bottom: PreferredSize(
        // ⚠️ 1.99.25（用户实机反馈：深色下往下划，头部玻璃的描边+填充整块消失）：
        // 这里**必须**声明 0，不能写真实高度。
        //
        // `pinned: false` 的 SliverAppBar 只要一开始滚动就会算
        //   bottomOpacity = clampDouble(visibleMainHeight / _bottomHeight, 0, 1) < 1
        // （app_bar.dart 的 `_SliverAppBarDelegate.build`），Flutter 随即把整个
        // `bottom`（= 我们这摞玻璃头部）包进 `Opacity` —— 一层离屏 saveLayer。
        // 玻璃是 BackdropFilter：进了 saveLayer 就采不到底景，**描边与填充一起
        // 消失**，只剩文字（文字还会被那层顺带压暗几个 %，所以肉眼看着「就是
        // 玻璃没了」）。声明 0 高 → 除数为 0 → 上式恒为 1.0 → 永不进 Opacity 分支。
        //
        // 高度改由 `expandedHeight` / `collapsedHeight` 表达后，delegate 的
        // minExtent / maxExtent / extraToolbarHeight 与「按真实高度声明」逐值
        // 相同，滚动行为、reveal 手感都不变。
        preferredSize: Size.fromHeight(0),
        // 垫页面背景色：半开时内容会从透明头部后穿过，文字叠文字没法读
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: child,
        ),
      ),
    );
  }
}
