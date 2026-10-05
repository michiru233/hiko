import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/ui/widgets/album_card.dart';
import 'package:hiko/ui/widgets/hiko_glass.dart';
// 只有本文件（门面的回归锁）可以直接依赖第三方库：锁的就是「门面把参数喂给了
// 着色器什么」。业务代码一律只 import hiko_glass.dart。
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

/// 1.99.22：HikoGlass 门面的回归锁。
///
/// 这里锁的全是**在 flutter_test 里看不出来、也不会有别的测试拦住**的退化：
/// - 两档的质量 / 图层映射被调换 → 浮层失去质感，或长列表逐卡自建图层掉帧；
/// - 专辑卡被从 tile 档改成 surface 档 → 主网格静默性能回退；
/// - animationDuration 失效 → 选中反馈静默退化成瞬变（album_card_test 不覆盖）；
/// - solid 模式漏回着色器路径 → 双态胶囊的激活态又变成半透明玻璃。
///
/// 之所以用纯函数 + 公开字段来断言，是因为上述退化**在测试环境里渲染结果完全
/// 一样**（Impeller 不可用，两条路径都降级成普通子树），只能锁参数本身。

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

    test('两档的取值互不相同，没有被写成同一个', () {
      expect(
        hikoGlassQuality(HikoGlassTier.surface),
        isNot(hikoGlassQuality(HikoGlassTier.tile)),
      );
      expect(
        hikoGlassUseOwnLayer(HikoGlassTier.surface),
        isNot(hikoGlassUseOwnLayer(HikoGlassTier.tile)),
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
