import 'package:flutter/material.dart';

import '../screens/fullscreen_player_screen.dart';

// 全屏播放页转场（1.88.0）
//
// ## 为什么不用平台默认转场
// macOS 默认解析到 `CupertinoPageTransitionsBuilder`——**整页横向滑入**。
// 对「唱片播放页」没有左右层级隐喻：音声库与「正在播放」之间是**上下**（底部
// 播放条 → 全屏）关系，不是左右关系。
//
// 更关键的是重影：1.84 起启用自定义背景图时，全屏页 Scaffold 是
// `Colors.transparent`（刻意透出根层 BackgroundLayer），而 `MaterialPageRoute`
// `opaque = true` 只在**动画进行中**绘制下层路由、动画一结束即停止绘制。
// 透明页面 + 下层仍被绘制 = 过渡全程两页叠加，结尾再一次性丢弃 → 观感是
// 「重影一段，然后啪地硬切」。
//
// ## 改法
// 被覆盖的那一页（首页 / 详情页）在 **150ms** 内快速退场（淡出 + 0.98 微缩），
// 把重影窗口压到 150ms 以内；全屏页从底部 **8px** 升起淡入，
// 250ms 打开 / 200ms 关闭（关闭要让路，比打开快）。
//
// ## 1.88.1：为什么退场不带模糊
// transitions.dev 的 page-slide 配方给的是 3px blur，那是写给 CSS 的——浏览器
// 合成器处理模糊的成本，和 Skia 在桌面 Retina 窗口上跑全屏高斯不是一个量级。
// 这里翻车的方式是：`ImageFiltered` 要求先把子树栅格化进离屏图层，于是被覆盖页
// 里所有重滤波（二十来张封面 σ20 + 光晕 σ80/σ55）全被强制每帧重新栅格化，
// 外面再叠一层全屏高斯。换来的只是"更软的淡出观感"——性价比是负的。
// 应当翻译它的**原则**（位移小、时长 250ms、smooth-out、关闭快于打开），
// 而不是照抄那个数字。
//
// 注意：退场效果必须由「被覆盖的那一级」自己的转场器实现（它的
// `secondaryAnimation` 才是驱动退场的那一根），所以本文件的
// [HikoPageTransitionsBuilder] 挂在全局 `pageTransitionsTheme` 上。
//
// ## 参数来源（transitions.dev motion token）
// | 量 | 值 | token |
// |---|---|---|
// | 打开时长 | 250ms | `--duration-fast` |
// | 关闭时长 | 200ms | open/close 不对称 |
// | 退场窗口 | 150ms | `--duration-quick` |
// | 缓动 | `cubic-bezier(0.22, 1, 0.36, 1)` | `--ease-smooth-out` |
// | 升起距离 | 8px（返回减半） | `--distance-base` |
// | 退场缩放 | 0.98 | `--scale-small` |
// | 退场模糊 | 不使用 | 1.88.1 移除，见上方「为什么退场不带模糊」 |

/// 供转场器识别「这是全屏播放页」的路由名
const String fullscreenPlayerRouteName = 'fullscreenPlayer';

/// 打开 250ms（duration-fast）；关闭 200ms（关闭要让路，比打开快）
const Duration playerEnterDuration = Duration(milliseconds: 250);
const Duration playerExitDuration = Duration(milliseconds: 200);

/// ease-smooth-out：cubic-bezier(0.22, 1, 0.36, 1)
const Cubic _easeSmoothOut = Cubic(0.22, 1.0, 0.36, 1.0);

/// distance-base：入场升起 8px，返回时减半
const double _risePixels = 8.0;

/// scale-small：被覆盖时的退场微缩
const double _exitScale = 0.98;

/// duration-quick：退场窗口 150ms。转场总长按 250ms 计，
/// 即退场只占动画的前 60%，其余时间下层已不可见。
const double _exitWindowFraction = 150 / 250;

/// 全屏播放页路由：只在时长上区别于 MaterialPageRoute，
/// 转场本体由 [HikoPageTransitionsBuilder] 提供（走 theme）。
class FullscreenPlayerRoute<T> extends MaterialPageRoute<T> {
  FullscreenPlayerRoute()
      : super(
          builder: (context) => const FullscreenPlayerScreen(),
          settings: const RouteSettings(name: fullscreenPlayerRouteName),
        );

  @override
  Duration get transitionDuration => playerEnterDuration;

  @override
  Duration get reverseTransitionDuration => playerExitDuration;
}

/// 应用统一转场器。
///
/// - **入场**（`animation` 0→1）：全屏播放页从底部 8px 升起并淡入；
///   其余路由同样走这套（移动端专辑详情页），保持全应用动效语言一致。
/// - **退场**（`secondaryAnimation` 0→1，本路由被新路由覆盖时）：
///   淡出 + 0.98 微缩 + 3px 模糊，且**前载**到前 150ms——这是消除重影的关键。
class HikoPageTransitionsBuilder extends PageTransitionsBuilder {
  const HikoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 系统「减弱动态效果」打开时不做转场（对齐全屏页唱片旋转的既有守卫）
    if (MediaQuery.disableAnimationsOf(context)) return child;

    // 返回（关闭）时位移减半：让路，不做全幅度的反向运动
    final reverse = animation.status == AnimationStatus.reverse;
    final distance = reverse ? _risePixels / 2 : _risePixels;

    // 一层 child、多个变换叠套——与 Flutter 内置转场器同法，绝不重复构建子树
    return _CoveredPageExit(
      secondaryAnimation: secondaryAnimation,
      child: _EnteringPageRise(
        animation: animation,
        distance: distance,
        child: child,
      ),
    );
  }
}

/// 前载曲线：把整段动作压进总时长的前 [window] 比例，
/// 之后停在终值。用于让「被覆盖的页」远早于转场结束就退干净。
class _FrontLoadedCurve extends Curve {
  const _FrontLoadedCurve(this.window);

  final double window;

  @override
  double transform(double t) => (t / window).clamp(0.0, 1.0);
}

/// 被覆盖页的退场：淡出 + 微缩，前载到退场窗口内。
///
/// **不挂任何模糊层**——见下方 cycle 说明。退场的表达靠淡出与 0.98 微缩，
/// 二者都能走合成器，不需要把子树重新栅格化。
class _CoveredPageExit extends StatelessWidget {
  const _CoveredPageExit({
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final progress = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const _FrontLoadedCurve(_exitWindowFraction),
      reverseCurve: const _FrontLoadedCurve(_exitWindowFraction),
    );
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final t = progress.value;
        // 静息态（没有被覆盖）：原样交还子树，不叠任何图层——零成本。
        // 这一层挂在全局转场器上、每个路由都在，绝不能在常态下留着高斯模糊。
        if (t <= 0.001) return child!;
        final opacity = 1.0 - t;
        // 已褪到看不见：只留一层透明度为 0，省掉缩放与模糊
        if (opacity <= 0.01) return Opacity(opacity: 0.0, child: child);
        // 只有缩放，绝不加模糊层。
        //
        // 1.88.1 移除了 1.88.0 的退场模糊：`ImageFiltered` 要求把子树先栅格化进
        // 离屏图层再做高斯——被覆盖页里那二十来张封面模糊（隐私模糊 σ20，默认
        // 每次启动开启）与 σ80/σ55 的氛围光晕会被**强制每帧重新栅格化一遍**，
        // 外面再叠一层全屏高斯。机器再快也扛不住这种每帧同步工作量。
        // 去掉模糊后子树可以被复用，淡出 + 微缩已足够表达"退到后面去"。
        final scale = 1.0 - (1.0 - _exitScale) * t;
        Widget out = child!;
        if ((scale - 1.0).abs() > 0.0005) {
          out = Transform.scale(scale: scale, child: out);
        }
        return Opacity(opacity: opacity, child: out);
      },
      child: child,
    );
  }
}

/// 入场页的底部升起 + 淡入。
class _EnteringPageRise extends StatelessWidget {
  const _EnteringPageRise({
    required this.animation,
    required this.distance,
    required this.child,
  });

  final Animation<double> animation;
  final double distance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(parent: animation, curve: _easeSmoothOut);
    return AnimatedBuilder(
      animation: eased,
      builder: (context, child) {
        final t = eased.value;
        // 到位后原样交还，不在常态留位移图层
        if (t >= 0.999) return child!;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1.0 - t) * distance),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
