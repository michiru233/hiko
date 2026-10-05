import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

import '../theme.dart';

/// 玻璃档位。
///
/// 分档的唯一理由是**渲染代价相差一个量级**，而项目里两类用途的代价预算完全不同：
/// 浮层/栏是「少量、静止」的面，长列表卡片是「大量、滚动中」的面。
enum HikoGlassTier {
  /// 浮层与栏：右键菜单、详情面板、详情抽屉、播放栏、移动端底栏。
  ///
  /// premium 档 + 自建渲染图层，走满血多 pass 管线。
  surface,

  /// 长列表卡片：专辑卡、在线卡、首页各类列表卡。
  ///
  /// standard 档 + 共享图层，走单 pass 轻量着色器。
  tile,
}

/// 档位 → 渲染质量。
///
/// 纯函数，公开给回归锁直接断言：把两档的质量搞混会让长列表掉帧或让浮层失去质感，
/// 而这两种退化在 `flutter_test` 里都看不出来，只能靠锁住映射关系。
lg.GlassQuality hikoGlassQuality(HikoGlassTier tier) =>
    tier == HikoGlassTier.surface
        ? lg.GlassQuality.premium
        : lg.GlassQuality.standard;

/// 档位 → 是否自建渲染图层（`useOwnLayer`）。
///
/// - 浮层/栏**必须** `true`：premium 档若既不自建图层、又没有 `LiquidGlassLayer`
///   祖先，调试构建会命中 `LiquidGlassBlendGroup` 里的断言。项目不在
///   `main()` 里插全局图层（不需要 `LiquidGlassWidgets.wrap()`），所以自建是唯一解。
/// - 长列表卡片**必须** `false`：逐卡自建图层会让 GPU 显存随卡片数线性增长，
///   一屏几十张卡就是几十个独立合成层。
bool hikoGlassUseOwnLayer(HikoGlassTier tier) => tier == HikoGlassTier.surface;

/// 档位 → 模糊强度。
///
/// 纯函数，公开给回归锁直接断言。**这是性能契约里最关键的一条**：
/// `tile` 档必须为 `0`。只要大于 0，每个实例都会 push 一个 `BackdropFilterLayer`
/// 去实时模糊背后内容并强制成为独立合成层 —— 长列表里就是逐卡实时模糊，
/// 而卡片上真正能看见玻璃的面积很小（顶部被封面盖住），等于为看不出来的效果
/// 付最高档的代价。1.99.22 专辑卡滑动卡顿即由此而来。
///
/// `surface` 档是静止的浮层 / 栏，数量少、面积大、背景可见，实时模糊是它最抓眼的
/// 特征，代价可以接受。
double hikoGlassBlur(HikoGlassTier tier) =>
    tier == HikoGlassTier.surface ? 20 : 0;

/// 档位 → 玻璃基色。沿用 [HikoColors] 既有的玻璃 token，不另起一套配色。
Color hikoGlassTint(HikoGlassTier tier, {required bool isDark}) {
  final surface = tier == HikoGlassTier.surface;
  if (isDark) {
    return surface ? HikoColors.darkGlassSurface : HikoColors.darkGlassCard;
  }
  return surface ? HikoColors.lightGlassSurface : HikoColors.lightGlassCard;
}

/// 档位 → 描边色。
///
/// 浮层用可见高光边（`GlassBorder`），列表卡片用更弱的微光边（`GlassBorderSubtle`），
/// 与 1.99.21 之前 faux-glass 卡片的选择保持一致。
Color hikoGlassBorder(HikoGlassTier tier, {required bool isDark}) {
  final surface = tier == HikoGlassTier.surface;
  if (isDark) {
    return surface
        ? HikoColors.darkGlassBorder
        : HikoColors.darkGlassBorderSubtle;
  }
  return surface
      ? HikoColors.lightGlassBorder
      : HikoColors.lightGlassBorderSubtle;
}

/// 玻璃拟态容器的统一门面。
///
/// 把 `liquid_glass_widgets` 挡在这一层后面：业务代码只 import 本文件，
/// 不直接依赖第三方库 API。这样库升级（该库 1.0.0 → 1.9.0 已发 21 版，
/// breaking change 集中在早期）或将来换库时，改动收敛在单个文件。
///
/// 行为契约（两档的差异全部由 [HikoGlassTier] 决定）：
///
/// | | [HikoGlassTier.surface] | [HikoGlassTier.tile] |
/// |---|---|---|
/// | 质量 | premium（满血多 pass） | standard（单 pass 轻量表） |
/// | 渲染图层 | 自建（`useOwnLayer: true`） | 共享（不建图层） |
/// | 模糊 `blur` | 20 | **0** |
/// | 适用 | 静止浮层/栏 | 滚动中的长列表 |
///
/// **档位差异里最容易搞错的是 `blur`，它才是性能开关**（详见 [HikoGlass.blur]）：
/// 1.99.22 的专辑卡卡顿不是因为「库不行」，而是因为 tile 档沿用了 surface 档的
/// `blur = 20`，于是每张卡都在**逐帧实时模糊背后内容**。tile 档置 0 后走
/// `_paintGlassContent` 直画分支，不建合成层、不模糊背景，但程序化的边缘光 /
/// Fresnel / 立体斜面全部保留 —— 卡片上看得见的那点玻璃感大多来自这些程序化项，
/// 而卡片顶部本来就被封面盖住，实时模糊掉的可见面积很小。
///
/// 注 1：**不传 `backgroundKey`**。轻量档的 `backgroundKey` 只控制「采样 ticker」——
/// 它用于把**静止**背景一次性采样复用，省掉逐帧重采；不传就不会启动该 ticker。
/// 但这**不等于**不捕获背景：只要 `blur > 0`，`paint()` 仍会对每个实例
/// `pushLayer(BackdropFilterLayer)` 实时模糊。二者是独立的两件事，
/// 1.99.22 我把它们混为一谈，才误以为 tile 档接玻璃天然安全。
///
/// 注 2：在 `flutter_test` 里，Impeller 不可用，两条路径都会自动降级成普通子树
/// （`LiquidGlassBlendGroup` 在 `!ImageFilter.isShaderFilterSupported` 时直接透传），
/// 因此玻璃控件放进被测试覆盖的界面不会打穿测试基线 —— 代价是**档位参数搞错在
/// 测试里完全看不出来**，所以映射关系一律抽成公开纯函数单独锁（见 [hikoGlassBlur]）。
class HikoGlass extends StatelessWidget {
  const HikoGlass({
    super.key,
    required this.child,
    this.tier = HikoGlassTier.surface,
    this.borderRadius = 16,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.blur,
    this.thickness = 28,
    this.tint,
    this.borderColor,
    this.borderWidth = 0.8,
    this.boxShadow,
    this.clipBehavior = Clip.none,
    this.solid = false,
    this.animationDuration,
    this.animationCurve = Curves.easeOut,
  });

  final Widget child;
  final HikoGlassTier tier;

  /// 圆角半径。传入大于等于宽高一半的值即得胶囊/圆形（superellipse 会自行收敛）。
  final double borderRadius;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  /// 玻璃厚度，透传给着色器。
  final double thickness;

  /// 模糊强度。为 null 时按 [tier] 取 [hikoGlassBlur] 的默认值。
  ///
  /// **这是本门面最贵的一个参数**：只要 `> 0`，`LightweightLiquidGlass` 就会为
  /// **每一个实例** `pushLayer(BackdropFilterLayer)`，逐帧实时模糊它背后的内容
  /// 并叠加饱和增强矩阵，同时强制该控件成为独立合成层。放进滚动网格里就是
  /// 「每张卡一次 sigma20 高斯模糊」——1.99.22 专辑卡卡顿的根因。
  ///
  /// 置 `0` 时走 `_paintGlassContent` 直画分支：不建合成层、不模糊背景，
  /// 但程序化的边缘光 / Fresnel / 立体斜面**全部保留**。
  final double? blur;

  /// 覆盖玻璃基色。为 null 时按 [tier] + 亮暗取 [HikoColors] 的玻璃 token。
  final Color? tint;

  /// 覆盖描边色。为 null 时按 [tier] + 亮暗取 token。
  final Color? borderColor;
  final double borderWidth;

  /// 外阴影。**不计入玻璃本身**：由门面在外层用一个透明 `Container` 画，
  /// 避免阴影被玻璃自身的模糊采样污染出脏边。
  final List<BoxShadow>? boxShadow;

  final Clip clipBehavior;

  /// 走**实心**而不是玻璃：只画 tint + 描边的圆角矩形，不建图层、不跑着色器。
  ///
  /// 给「常态玻璃 / 激活实心」这类双态控件用（首页的标签 chip、多选按钮）。
  /// 有了它，调用点一次 `HikoGlass` 就能表达两种状态，不必按状态拆成两个分支、
  /// 重复写一遍内边距与子节点。激活态本来就该是实心主色，做成玻璃反而会透出
  /// 背景、削弱「已选中」的力度。
  final bool solid;

  /// 非 null 时对 tint / 描边色 / 描边宽度做隐式补间。
  ///
  /// 存在的唯一理由：专辑卡原本用 `AnimatedContainer` 把选中态的**颜色、描边、
  /// 阴影**一起做了 300ms 过渡。本门面是无状态的，若不做补间，换成玻璃后选中
  /// 反馈会**静默退化成瞬变**——而 `album_card_test.dart` 里没有任何断言能拦住
  /// 这种退化（它只涉及动画轮询参数）。
  ///
  /// 代价：补间期间每帧重建一次着色器参数，仅发生在选中/取消选中那几百毫秒内。
  /// 阴影也参与补间（选中是彩色外发光、常态是黑色投影，两者互斥）。
  final Duration? animationDuration;
  final Curve animationCurve;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveTint = tint ?? hikoGlassTint(tier, isDark: isDark);
    final effectiveBorder = borderColor ?? hikoGlassBorder(tier, isDark: isDark);

    final duration = animationDuration;
    final glass = duration == null
        ? _buildGlass(
            effectiveTint,
            effectiveBorder,
            borderWidth,
            boxShadow ?? const <BoxShadow>[],
          )
        : _AnimatedGlass(
            duration: duration,
            curve: animationCurve,
            tint: effectiveTint,
            borderColor: effectiveBorder,
            borderWidth: borderWidth,
            shadows: boxShadow ?? const <BoxShadow>[],
            builder: _buildGlass,
          );

    return _wrapMargin(glass);
  }

  Widget _wrapMargin(Widget glass) {
    final gap = margin;
    return gap == null ? glass : Padding(padding: gap, child: glass);
  }

  Widget _buildGlass(
    Color tintColor,
    Color borderColor,
    double borderWidth,
    List<BoxShadow> shadows,
  ) {
    final Widget glass = solid
        ? Container(
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: tintColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: borderColor, width: borderWidth),
            ),
            child: child,
          )
        : lg.GlassContainer(
            width: width,
            height: height,
            padding: padding,
            clipBehavior: clipBehavior,
            shape: lg.LiquidRoundedSuperellipse(
              borderRadius: borderRadius,
              side: BorderSide(color: borderColor, width: borderWidth),
            ),
            settings: lg.LiquidGlassSettings(
              glassColor: tintColor,
              blur: blur ?? hikoGlassBlur(tier),
              thickness: thickness,
            ),
            quality: hikoGlassQuality(tier),
            useOwnLayer: hikoGlassUseOwnLayer(tier),
            child: child,
          );

    if (shadows.isEmpty) return glass;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: shadows,
      ),
      child: glass,
    );
  }
}

/// 对 tint / 描边色 / 描边宽度 / 阴影列表做隐式补间，
/// 供 [HikoGlass.animationDuration] 使用。
class _AnimatedGlass extends ImplicitlyAnimatedWidget {
  const _AnimatedGlass({
    required this.tint,
    required this.borderColor,
    required this.borderWidth,
    required this.shadows,
    required this.builder,
    required super.duration,
    super.curve,
  });

  final Color tint;
  final Color borderColor;
  final double borderWidth;
  final List<BoxShadow> shadows;
  final Widget Function(
    Color tint,
    Color borderColor,
    double borderWidth,
    List<BoxShadow> shadows,
  ) builder;

  @override
  AnimatedWidgetBaseState<_AnimatedGlass> createState() =>
      _AnimatedGlassState();
}

class _AnimatedGlassState extends AnimatedWidgetBaseState<_AnimatedGlass> {
  ColorTween? _tint;
  ColorTween? _borderColor;
  Tween<double>? _borderWidth;
  _ShadowListTween? _shadows;

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _tint = visitor(
      _tint,
      widget.tint,
      (dynamic value) => ColorTween(begin: value as Color),
    ) as ColorTween?;
    _borderColor = visitor(
      _borderColor,
      widget.borderColor,
      (dynamic value) => ColorTween(begin: value as Color),
    ) as ColorTween?;
    _borderWidth = visitor(
      _borderWidth,
      widget.borderWidth,
      (dynamic value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
    _shadows = visitor(
      _shadows,
      widget.shadows,
      (dynamic value) =>
          _ShadowListTween(begin: value as List<BoxShadow>),
    ) as _ShadowListTween?;
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        _tint!.evaluate(animation)!,
        _borderColor!.evaluate(animation)!,
        _borderWidth!.evaluate(animation),
        _shadows!.evaluate(animation),
      );
}

/// [BoxShadow] 列表的线性插值。
///
/// 单独写一个是因为选中态与常态的阴影**项数可能不同**（选中是彩色外发光、
/// 常态是黑色投影，互斥只出一项）。[BoxShadow.lerpList] 已经处理了长度不一致
/// 的情况（短的一侧补零长度透明阴影），这里只是把它接进 `Tween` 体系。
class _ShadowListTween extends Tween<List<BoxShadow>> {
  // `end` 由 ImplicitlyAnimatedWidget 的框架机制赋值，构造函数只收初值。
  _ShadowListTween({super.begin});

  @override
  List<BoxShadow> lerp(double t) =>
      BoxShadow.lerpList(begin, end, t) ?? const <BoxShadow>[];
}
