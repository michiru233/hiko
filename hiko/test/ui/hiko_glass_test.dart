import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/album_card.dart';
import 'package:hiko/ui/widgets/hiko_glass.dart';
// 只有本文件（门面的回归锁）可以直接依赖第三方库：锁的就是「门面把参数喂给了
// 着色器什么」。业务代码一律只 import hiko_glass.dart。
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

/// 1.99.22：HikoGlass 门面的回归锁。
///
/// 这里锁的全是**在 flutter_test 里看不出来、也不会有别的测试拦住**的退化：
/// - 两档的质量 / 图层映射被调换 → 浮层失去质感，或长列表逐卡自建图层掉帧；
/// - **tile 档的 blur 被写成非 0** → 每张卡逐帧实时模糊背景（1.99.23 修的移动端卡顿）；
/// - **深色下 tile 档又走着色器** → 每张卡一圈刺眼的白色结构边（1.99.24 修的深色边框）；
/// - **深色卡衬底台阶被抹平** → 压掉白边后卡片失去可辨认的卡面（1.99.24）；
/// - 专辑卡被从 tile 档改成 surface 档 → 主网格静默性能回退；
/// - animationDuration 失效 → 选中反馈静默退化成瞬变（album_card_test 不覆盖）；
/// - solid 模式漏回着色器路径 → 双态胶囊的激活态又变成半透明玻璃。
///
/// 之所以用纯函数 + 公开字段来断言，是因为上述退化**在测试环境里渲染结果完全
/// 一样**（Impeller 不可用，两条路径都降级成普通子树），只能锁参数本身。
/// 1.99.23 的卡顿就是这么漏出去的：1.99.22 只锁了质量与图层，没锁 blur，
/// 而 blur 才是真正的性能开关。1.99.24 反过来补了一条**能端到端观测**的锁
/// ——「树里到底有没有 `lg.GlassContainer`」。

Album _album(String id) => Album(
  id: id,
  sourcePath: '/x/$id',
  title: id,
  date: DateTime(2026),
  tracks: [Track(index: 0, name: 'n', url: 'file:///$id.mp3')],
);

/// 取出树里第一个 [HikoGlass] 外层实际生效的着色器基色。
Color _shaderTint(WidgetTester tester) {
  final container = tester.widget<lg.GlassContainer>(
    find.byType(lg.GlassContainer),
  );
  return container.settings!.glassColor;
}

/// 取出树里第一个 [HikoGlass] 外层的实际模糊强度。
///
/// 这是 1.99.23 补上的那条锁：`LiquidGlassSettings.blur` 默认是 5，
/// 一旦门面没把档位默认值喂进来（`blur: blur` 而不是 `blur: blur ?? hikoGlassBlur(tier)`），
/// 测试里所有断言照样全绿，真机上就是逐卡实时模糊。
double _shaderBlur(WidgetTester tester) {
  final container = tester.widget<lg.GlassContainer>(
    find.byType(lg.GlassContainer),
  );
  return container.settings!.blur;
}

void main() {
  group('档位 → 渲染参数映射（性能契约）', () {
    test('surface 档 = premium + 自建图层', () {
      expect(hikoGlassQuality(HikoGlassTier.surface), lg.GlassQuality.premium);
      expect(hikoGlassUseOwnLayer(HikoGlassTier.surface), isTrue);
    });

    test('tile 档 = standard + 不自建图层（长列表逐卡建图层会吃光显存）', () {
      expect(hikoGlassQuality(HikoGlassTier.tile), lg.GlassQuality.standard);
      expect(hikoGlassUseOwnLayer(HikoGlassTier.tile), isFalse);
    });

    test('tile 档 blur 必须是 0（>0 就是逐卡 BackdropFilterLayer 实时模糊）', () {
      expect(
        hikoGlassBlur(HikoGlassTier.tile),
        0,
        reason: '卡上能看见玻璃的面积很小（顶部被封面盖住），'
            '为看不出来的实时模糊付最高代价就是移动端滑动卡顿的来源',
      );
    });

    test('surface 档 blur 大于 0（静止浮层的实时模糊是它的核心观感）', () {
      expect(hikoGlassBlur(HikoGlassTier.surface), greaterThan(0));
    });

    test('两档的取值互不相同，没有被写成同一个', () {
      expect(
        hikoGlassQuality(HikoGlassTier.surface),
        isNot(hikoGlassQuality(HikoGlassTier.tile)),
      );
      expect(
        hikoGlassUseOwnLayer(HikoGlassTier.surface),
        isNot(hikoGlassUseOwnLayer(HikoGlassTier.tile)),
      );
      expect(
        hikoGlassBlur(HikoGlassTier.surface),
        isNot(hikoGlassBlur(HikoGlassTier.tile)),
      );
    });
  });

  group('深色下 tile 档不走着色器（1.99.24：那圈白边其实是着色器写死的）', () {
    // 轻量着色器的结构白边由 `uBackdropLuma` 开合，而它是库里的常量
    // `isDark ? 0.15 : 0.85` —— 深色 0.15 让白边满血、浅色 0.85 让它近乎消失。
    // `LiquidGlassSettings` 碰不到它，所以深色卡只能不走着色器。
    test('surface 档浅深都走着色器', () {
      expect(hikoGlassUsesShader(HikoGlassTier.surface, isDark: false), isTrue);
      expect(hikoGlassUsesShader(HikoGlassTier.surface, isDark: true), isTrue);
    });

    test('tile 档浅色走、深色不走', () {
      expect(hikoGlassUsesShader(HikoGlassTier.tile, isDark: false), isTrue);
      expect(
        hikoGlassUsesShader(HikoGlassTier.tile, isDark: true),
        isFalse,
        reason: '深色下走着色器 = 每张卡一圈 0.65 alpha 的白色结构边，'
            '在近黑的卡底上就是一条刺眼的亮环（实测峰值 168，卡内底色才 31）',
      );
    });

    test('浅色下两档都走着色器（浅色观感已满意，不要动）', () {
      for (final tier in HikoGlassTier.values) {
        expect(hikoGlassUsesShader(tier, isDark: false), isTrue);
      }
    });

    test('两档只在深色下分开，浅色下不能分（否则浅色卡会平掉）', () {
      expect(
        hikoGlassUsesShader(HikoGlassTier.surface, isDark: true),
        isNot(hikoGlassUsesShader(HikoGlassTier.tile, isDark: true)),
      );
      expect(
        hikoGlassUsesShader(HikoGlassTier.surface, isDark: false),
        hikoGlassUsesShader(HikoGlassTier.tile, isDark: false),
      );
    });

    /// 这是整份文件里**唯一能端到端观测**的一条：树里到底有没有 `lg.GlassContainer`。
    Future<void> pumpTier(
      WidgetTester tester,
      HikoGlassTier tier, {
      required bool dark,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
            body: Center(
              child: HikoGlass(
                tier: tier,
                child: const SizedBox(width: 60, height: 40),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('深色 tile 档渲染时不建着色器容器', (tester) async {
      await pumpTier(tester, HikoGlassTier.tile, dark: true);
      expect(
        find.byType(lg.GlassContainer),
        findsNothing,
        reason: '深色卡必须退回我们自己的实心面；建了着色器容器就等于把白边带回来',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('浅色 tile 档照旧建着色器容器（回归保护）', (tester) async {
      await pumpTier(tester, HikoGlassTier.tile, dark: false);
      expect(find.byType(lg.GlassContainer), findsOneWidget);
    });

    testWidgets('深色 surface 档照旧建着色器容器（浮层不在本次修正范围）', (tester) async {
      await pumpTier(tester, HikoGlassTier.surface, dark: true);
      expect(find.byType(lg.GlassContainer), findsOneWidget);
    });

    testWidgets('专辑卡在深色下不建着色器容器', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 400,
                child: AlbumCard(
                  album: _album('rj000'),
                  multiMode: false,
                  selected: false,
                  onTap: () {},
                  onContextMenu: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(HikoGlass), findsWidgets);
      expect(find.byType(lg.GlassContainer), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('深色卡衬底阶梯（1.99.24：不能只靠边缘定义自己）', () {
    /// 把 token 按自身 alpha 合成到指定底色上（与 Flutter 的画法一致）。
    Color over(Color fg, Color bg) {
      final a = fg.a;
      double mix(double f, double b) => a * f + (1 - a) * b;
      return Color.from(
        alpha: 1,
        red: mix(fg.r, bg.r),
        green: mix(fg.g, bg.g),
        blue: mix(fg.b, bg.b),
      );
    }

    double luma(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;

    test('深色卡比页面底亮出可感知的台阶，但没亮成灰块', () {
      final card = over(hikoGlassTint(HikoGlassTier.tile, isDark: true),
          HikoColors.darkBg);
      final lift = (luma(card) - luma(HikoColors.darkBg)) * 255;
      expect(
        lift,
        greaterThanOrEqualTo(6),
        reason: '深色卡原先只比页面底亮 2 —— 把着色器白边压掉之后，'
            '卡片就只剩一条 8% 白描边可辨认，必须先把衬底垫起来',
      );
      expect(
        lift,
        lessThanOrEqualTo(14),
        reason: '再往上加就成了深色里的灰块',
      );
    });

    test('浅色卡的相对台阶同量级（两边观感对齐）', () {
      final darkCard =
          over(hikoGlassTint(HikoGlassTier.tile, isDark: true), HikoColors.darkBg);
      final lightCard = over(
          hikoGlassTint(HikoGlassTier.tile, isDark: false), HikoColors.lightBg);
      final darkLift = (luma(darkCard) - luma(HikoColors.darkBg)) * 255;
      final lightLift = (luma(lightCard) - luma(HikoColors.lightBg)) * 255;
      expect(
        (darkLift - lightLift).abs(),
        lessThan(10),
        reason: '两边台阶差太多，深浅两张卡就不会是一对兄弟',
      );
    });
  });

  group('档位 → 取色', () {
    test('surface 与 tile 取不同的玻璃 token（浅色 / 深色各一遍）', () {
      for (final isDark in [false, true]) {
        final surfaceTint = hikoGlassTint(HikoGlassTier.surface, isDark: isDark);
        final tileTint = hikoGlassTint(HikoGlassTier.tile, isDark: isDark);
        expect(surfaceTint, isNot(tileTint));

        final surfaceBorder = hikoGlassBorder(
          HikoGlassTier.surface,
          isDark: isDark,
        );
        final tileBorder = hikoGlassBorder(HikoGlassTier.tile, isDark: isDark);
        expect(surfaceBorder, isNot(tileBorder));
      }
    });

    test('同一个档位在浅色与深色下取色不同', () {
      for (final tier in HikoGlassTier.values) {
        expect(
          hikoGlassTint(tier, isDark: false),
          isNot(hikoGlassTint(tier, isDark: true)),
        );
        expect(
          hikoGlassBorder(tier, isDark: false),
          isNot(hikoGlassBorder(tier, isDark: true)),
        );
      }
    });
  });

  group('门面渲染路径', () {
    testWidgets('默认走玻璃路径（树里有着色器容器）', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: HikoGlass(child: SizedBox(width: 60, height: 40)),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(lg.GlassContainer), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('solid: true 时不建着色器容器，只画实心圆角矩形', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: HikoGlass(
                solid: true,
                child: SizedBox(width: 60, height: 40),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(lg.GlassContainer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('animationDuration 让基色走补间，而不是瞬变', (tester) async {
      const from = Color(0xFF112233);
      const to = Color(0xFFAABBCC);

      Widget host(Color tint) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: HikoGlass(
              tint: tint,
              animationDuration: const Duration(milliseconds: 300),
              child: const SizedBox(width: 60, height: 40),
            ),
          ),
        ),
      );

      await tester.pumpWidget(host(from));
      await tester.pump();
      expect(_shaderTint(tester), from);

      await tester.pumpWidget(host(to));
      await tester.pump(const Duration(milliseconds: 150));
      final mid = _shaderTint(tester);
      expect(mid, isNot(from), reason: '补间中不应还是起始色');
      expect(mid, isNot(to), reason: '补间中不应已经到终点色');

      await tester.pump(const Duration(milliseconds: 200));
      expect(_shaderTint(tester), to);
    });

    testWidgets('不传 animationDuration 时基色直接跟随（无补间）', (tester) async {
      const from = Color(0xFF112233);
      const to = Color(0xFFAABBCC);

      Widget host(Color tint) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: HikoGlass(
              tint: tint,
              child: const SizedBox(width: 60, height: 40),
            ),
          ),
        ),
      );

      await tester.pumpWidget(host(from));
      await tester.pump();
      await tester.pumpWidget(host(to));
      expect(_shaderTint(tester), to);
    });
  });

  group('档位默认值真的喂进了着色器（1.99.23：blur 是真正的性能开关）', () {
    Future<void> pumpTier(WidgetTester tester, HikoGlassTier tier) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HikoGlass(
                tier: tier,
                child: const SizedBox(width: 60, height: 40),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('tile 档渲染出的 blur 是 0', (tester) async {
      await pumpTier(tester, HikoGlassTier.tile);
      expect(
        _shaderBlur(tester),
        0,
        reason: '门面若把 blur 直接透传（漏掉 ?? hikoGlassBlur(tier)），'
            '这里会拿到 LiquidGlassSettings 的默认值 5 —— '
            '测试里毫无症状，真机上就是逐卡实时模糊',
      );
    });

    testWidgets('surface 档渲染出的 blur 大于 0', (tester) async {
      await pumpTier(tester, HikoGlassTier.surface);
      expect(_shaderBlur(tester), greaterThan(0));
    });

    testWidgets('显式传 blur 时压过档位默认值', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: HikoGlass(
                blur: 12,
                child: SizedBox(width: 60, height: 40),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        _shaderBlur(tester),
        12,
        reason: '首页工具栏那种静态胶囊仍需要按调用点微调；'
            '档位默认值必须让位于显式值',
      );
    });
  });

  group('专辑卡必须走 tile 档', () {
    testWidgets('专辑卡的玻璃是 tile 档（换成 surface 档就是主网格性能回退）', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 400,
                child: AlbumCard(
                  album: _album('rj000'),
                  multiMode: false,
                  selected: false,
                  onTap: () {},
                  onContextMenu: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final glass = tester.widgetList<HikoGlass>(find.byType(HikoGlass));
      expect(glass, isNotEmpty);
      for (final g in glass) {
        expect(
          g.tier,
          HikoGlassTier.tile,
          reason: '专辑卡在主滚动网格里，必须是 standard 轻量档',
        );
        expect(
          g.animationDuration,
          isNotNull,
          reason: '选中态的颜色/描边/阴影过渡不能丢',
        );
      }
    });
  });
}
