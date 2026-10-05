import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/online/online_favorites.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/screens/online_screen.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/detail_kit.dart';
import 'package:hiko/ui/widgets/hiko_glass.dart';
import 'package:hiko/ui/widgets/online_card_kit.dart';
import 'package:hiko/ui/widgets/online_cover.dart';
import 'package:hiko/ui/widgets/online_work_grid.dart';

/// 在线列表卡片的回归锁，分五块：
/// ① 封面必须取**原图**（主界面封面模糊的全部原因就是这里拿了 240×180 缩略图，
///    卡片在 Retina 上需要 400–520 物理像素，等于放大 2.4–2.9 倍）；
/// ② 收藏角标跟着歌单索引走；
/// ③ 1.99.21 胶囊化改版（元数据胶囊的内容 / 类别 / 配色）；
/// ④ 1.99.21 瀑布流（卡片高矮由内容决定、列数解析）；
/// ⑤ 1.99.23 卡面玻璃（必须与本地专辑卡同为 tile 档，否则两种卡片材质不一致）。
void main() {
  // 拦下所有封面请求：单测不该联网，也不该留下待处理的连接定时器
  late List<Uri> requested;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    privacyBlur.value = false; // 关掉隐私模糊，避免测试里多套一层高斯
    requested = [];
    HttpOverrides.global = _RecordingHttpOverrides(requested);
  });

  tearDown(() => HttpOverrides.global = null);

  OnlineWork work({int id = 1657200, String title = '测试作品'}) =>
      OnlineWork(id: id, title: title, circleName: 'サークル');

  /// 造一个带标签的作品。`withId: false` 用来模拟服务端只给名字的异常形态
  OnlineWork tagged(List<String> names, {bool withId = true, int id = 1657200}) =>
      OnlineWork(
        id: id,
        title: '测试作品',
        circleName: 'サークル',
        tags: [
          for (var i = 0; i < names.length; i++)
            OnlineTag(id: withId ? 100 + i : 0, name: names[i]),
        ],
      );

  /// 各条元数据都齐的作品：两个声优 + 社团 + RJ号 + 2小时25分钟 + 1.2万下载
  OnlineWork fullWork({int id = 1657200}) => OnlineWork(
        id: id,
        title: '测试作品',
        circleName: 'サークル',
        rjCode: 'RJ01318014',
        durationSeconds: 145 * 60,
        dlCount: 12345,
        vas: const ['声优A', '声优B'],
      );

  /// 宿主给一个**足够高**的框：卡片高度现在由内容决定（瀑布流），
  /// 撑不满只是留白，撑过头才会当场 `RenderFlex overflowed`。
  Widget host(Widget child, {double width = 200, double height = 900}) =>
      ProviderScope(
        child: MaterialApp(
          theme: buildHikoTheme(const AppSettings()),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, height: height, child: child),
            ),
          ),
        ),
      );

  /// 覆盖收藏索引（免去真实登录与网络）
  Widget hostWithFavorites(Widget child, OnlineFavorites index) => ProviderScope(
        overrides: [
          onlineFavoritesProvider.overrideWith((ref) => _StubFavorites(ref, index)),
        ],
        child: MaterialApp(
          theme: buildHikoTheme(const AppSettings()),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 200, height: 900, child: child),
            ),
          ),
        ),
      );

  group('封面清晰度（1.93.0 回归锁）', () {
    testWidgets('卡片请求的是原图（type=main），不是 240x240 缩略图', (tester) async {
      await tester.pumpWidget(
        host(OnlineWorkCard(work: work(), onTap: () {})),
      );
      await tester.pump();
      await tester.pump();

      final covers = requested
          .where((uri) => uri.path.contains('/api/cover/'))
          .toList();
      expect(covers, isNotEmpty, reason: '卡片应当去拉封面');
      for (final uri in covers) {
        expect(
          uri.query,
          'type=main',
          reason: '列表封面必须走原图；$uri 一旦变成 240x240 主界面就会再次糊掉',
        );
        expect(uri.toString(), isNot(contains('240x240')));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('同一个作品只请求一个封面地址（磁盘缓存只存一份）', (tester) async {
      await tester.pumpWidget(
        host(OnlineWorkCard(work: work(), onTap: () {})),
      );
      await tester.pump();
      await tester.pump();

      final unique = requested
          .where((uri) => uri.path.contains('/api/cover/'))
          .map((uri) => uri.toString())
          .toSet();
      expect(unique.length, 1, reason: '同一个作品只该有一个封面地址');
      expect(unique.single, endsWith('/api/cover/1657200.jpg?type=main'));
    });

    testWidgets('封面是精确的 1:1（1.99.21：不再靠内边距凑那 8px 余量）', (tester) async {
      await tester.pumpWidget(
        host(OnlineWorkCard(work: work(), onTap: () {})),
      );
      await tester.pump();

      // 固定高度的年代封面是 `Expanded`，只能靠「预算里的 8px 余量」间接控高度，
      // 所以当时的高度锁看的是「封面高 - 封面宽 == 8」。现在卡片是瀑布流、
      // 封面是 `AspectRatio(1)`，可以直接钉住它本身是正方形。
      final cover = tester.getSize(find.byType(OnlineCover));
      expect(cover.height, closeTo(cover.width, 0.001));
    });
  });

  group('卡面玻璃（1.99.23 与本地专辑卡对齐）', () {
    testWidgets('卡面有一层 tile 档玻璃（不能退回纯透明 Container）', (tester) async {
      await tester.pumpWidget(
        host(OnlineWorkCard(work: work(), onTap: () {})),
      );
      await tester.pump();

      final glass = tester.widgetList<HikoGlass>(find.byType(HikoGlass));
      expect(
        glass,
        isNotEmpty,
        reason: '在线卡摆在本专辑卡旁边必须是同一种材质，'
            '之前它是纯透明 Container（只有选中态一条描边）',
      );
      for (final g in glass) {
        expect(
          g.tier,
          HikoGlassTier.tile,
          reason: '在线卡片同样在主滚动网格里，必须是 standard 轻量档；'
              '写成 surface 档会逐卡自建渲染图层',
        );
        expect(
          g.animationDuration,
          isNotNull,
          reason: '选中态的颜色/描边过渡不能丢',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('选中态加粗描边并换成主色，未选中回到微光边', (tester) async {
      Widget card(bool selected) => host(
        OnlineWorkCard(work: work(), onTap: () {}, selected: selected),
      );

      await tester.pumpWidget(card(false));
      await tester.pump();
      final resting = tester.widget<HikoGlass>(find.byType(HikoGlass));
      expect(resting.borderWidth, lessThan(1.0), reason: '常态是微光边，不该抢眼');

      await tester.pumpWidget(card(true));
      await tester.pump(const Duration(milliseconds: 400));
      final active = tester.widget<HikoGlass>(find.byType(HikoGlass));
      expect(
        active.borderWidth,
        greaterThan(resting.borderWidth),
        reason: '选中态必须比常态更粗，否则「已选中」在网格里读不出来',
      );
      expect(active.borderColor, isNot(resting.borderColor));
    });
  });

  group('收藏角标', () {
    OnlinePlaylist playlist(String id, String name) =>
        OnlinePlaylist(id: id, name: name);

    testWidgets('不在任何歌单里：不显示角标', (tester) async {
      await tester.pumpWidget(
        hostWithFavorites(
          OnlineWorkCard(work: work(), onTap: () {}),
          OnlineFavorites(
            playlists: [playlist('liked', OnlinePlaylist.sysLiked)],
            worksById: {'liked': const []},
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_rounded), findsNothing);
    });

    testWidgets('在一个歌单里：点亮书签，不显示数量', (tester) async {
      await tester.pumpWidget(
        hostWithFavorites(
          OnlineWorkCard(work: work(), onTap: () {}),
          OnlineFavorites(
            playlists: [
              playlist('liked', OnlinePlaylist.sysLiked),
              playlist('done', '听完'),
            ],
            worksById: {
              'liked': [work()],
              'done': const [],
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(find.text('1'), findsNothing, reason: '只有一个歌单时不显示数量');
      expect(find.text('2'), findsNothing);
    });

    testWidgets('在多个歌单里：角标带数量', (tester) async {
      await tester.pumpWidget(
        hostWithFavorites(
          OnlineWorkCard(work: work(), onTap: () {}),
          OnlineFavorites(
            playlists: [
              playlist('liked', OnlinePlaylist.sysLiked),
              playlist('done', '听完'),
            ],
            worksById: {
              'liked': [work()],
              'done': [work()],
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('字幕角标与收藏角标可以并存，两态都无溢出', (tester) async {
      await tester.pumpWidget(
        hostWithFavorites(
          OnlineWorkCard(
            work: OnlineWork(id: 1657200, title: '测试作品', hasSubtitle: true),
            onTap: () {},
          ),
          OnlineFavorites(
            playlists: [playlist('done', '听完')],
            worksById: {
              'done': [work()],
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('字幕'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('卡面标签组（1.99.21：全部展示，不再截断）', () {
    testWidgets('开关关闭时不渲染任何标签', (tester) async {
      await tester.pumpWidget(
        host(
          OnlineWorkCard(
            work: tagged(['ASMR', '治愈']),
            onTap: () {},
            onTagTap: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ASMR'), findsNothing);
      expect(find.text('治愈'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('标签**全部**渲染，不再有 +N', (tester) async {
      const names = [
        '双声道立体声/人头麦',
        '亲热/甜蜜',
        '青梅竹马',
        '学生',
        'ASMR',
        '环绕音',
      ];
      await tester.pumpWidget(
        host(
          OnlineWorkCard(
            work: tagged(names),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
        ),
      );
      await tester.pump();

      for (final name in names) {
        expect(find.text(name), findsOneWidget, reason: '标签「$name」必须出现在卡面上');
      }
      expect(
        find.textContaining('+'),
        findsNothing,
        reason: '瀑布流换来了「全部展示」，`+N` 这一套复杂度应当已经删干净',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('点标签只触发筛选，不会连带打开详情', (tester) async {
      OnlineTag? tapped;
      var cardTaps = 0;
      await tester.pumpWidget(
        host(
          OnlineWorkCard(
            work: tagged(['ASMR']),
            onTap: () => cardTaps++,
            showTags: true,
            onTagTap: (t) => tapped = t,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('ASMR'));
      await tester.pump();

      expect(tapped?.name, 'ASMR');
      expect(tapped?.id, 100, reason: '筛选要的是 id');
      expect(cardTaps, 0, reason: '标签必须吃掉自己的点击，卡片不该被连带触发');
    });

    testWidgets('服务端只给了名字（id=0）的标签只能看，点了不筛选', (tester) async {
      var tagTaps = 0;
      await tester.pumpWidget(
        host(
          OnlineWorkCard(
            work: tagged(['ASMR'], withId: false),
            onTap: () {},
            showTags: true,
            onTagTap: (_) => tagTaps++,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('ASMR'));
      await tester.pump();

      expect(tagTaps, 0, reason: '没有 id 就没法发 /api/tags/{id}/works');
    });

    testWidgets('窄卡片（移动端 2 列）也全部渲染且不溢出', (tester) async {
      const names = [
        '双声道立体声/人头麦',
        '亲热/甜蜜',
        '青梅竹马',
        '学生',
        '环绕音',
      ];
      await tester.pumpWidget(
        host(
          OnlineWorkCard(
            work: tagged(names),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
          width: 150,
        ),
      );
      await tester.pump();

      for (final name in names) {
        expect(find.text(name), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: '窄卡片上换行，不该溢出');
    });
  });

  group('卡面标签：黑名单与菜单（1.95.0）', () {
    Widget hostWith(
      Widget card, {
      List<OnlineTag> blocked = const [],
      double scale = 1.0,
      double width = 200,
    }) =>
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => _StubSettings(blocked)),
          ],
          child: MaterialApp(
            theme: buildHikoTheme(const AppSettings()),
            builder: (context, inner) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: inner!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: width, height: 900, child: card),
              ),
            ),
          ),
        );

    testWidgets('全局字号放大到 1.30 时标签组仍不溢出', (tester) async {
      await tester.pumpWidget(
        hostWith(
          OnlineWorkCard(
            work: tagged([
              '双声道立体声/人头麦',
              '学生',
              '青梅竹马',
              'ASMR',
              '环绕音',
            ]),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
          scale: 1.3,
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: '字号放大后标签组不该溢出：换行必须是真的换行',
      );
    });

    testWidgets('被屏蔽的标签弱化显示：删除线，普通标签没有', (tester) async {
      await tester.pumpWidget(
        hostWith(
          OnlineWorkCard(
            work: tagged(['ASMR', '治愈']),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
          blocked: const [OnlineTag(id: 100, name: 'ASMR')],
        ),
      );
      await tester.pump();

      expect(
        tester.widget<Text>(find.text('ASMR')).style?.decoration,
        TextDecoration.lineThrough,
      );
      expect(
        tester.widget<Text>(find.text('治愈')).style?.decoration,
        isNot(TextDecoration.lineThrough),
      );
    });

    testWidgets('右键标签弹出三个动作：筛选 / 加入黑名单 / 复制标签名', (tester) async {
      await tester.pumpWidget(
        hostWith(
          OnlineWorkCard(
            work: tagged(['ASMR']),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
        ),
      );
      await tester.pump();

      await tester.tapAt(
        tester.getCenter(find.text('ASMR')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('按此标签筛选'), findsOneWidget);
      expect(find.text('加入黑名单'), findsOneWidget);
      expect(find.text('复制标签名'), findsOneWidget);
    });

    testWidgets('已在黑名单里的标签，菜单第二项变成「移出黑名单」', (tester) async {
      await tester.pumpWidget(
        hostWith(
          OnlineWorkCard(
            work: tagged(['ASMR']),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
          blocked: const [OnlineTag(id: 100, name: 'ASMR')],
        ),
      );
      await tester.pump();

      await tester.tapAt(
        tester.getCenter(find.text('ASMR')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('移出黑名单'), findsOneWidget);
      expect(find.text('加入黑名单'), findsNothing);
    });

    testWidgets('服务端只给名字（id=0）的标签连菜单都不给', (tester) async {
      await tester.pumpWidget(
        hostWith(
          OnlineWorkCard(
            work: tagged(['ASMR'], withId: false),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
        ),
      );
      await tester.pump();

      await tester.tapAt(
        tester.getCenter(find.text('ASMR')),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      // 既筛不了也屏蔽不了，给菜单等于给一个死操作
      expect(find.text('加入黑名单'), findsNothing);
      expect(find.text('按此标签筛选'), findsNothing);
    });
  });

  group('元数据胶囊（1.99.21）', () {
    /// 卡面上每一枚元数据胶囊的「文字 → 类别」映射。
    /// 按文字取类别而不是按位置取，是因为位置将来会调整，类别不会。
    Map<String, OnlinePillKind> pillKinds(WidgetTester tester) => {
          for (final pill
              in tester.widgetList<OnlinePill>(find.byType(OnlinePill)))
            pill.text: pill.kind,
        };

    testWidgets('每个声优一枚胶囊，社团 / RJ号 / 时长 / 下载量各一枚', (tester) async {
      await tester.pumpWidget(host(OnlineWorkCard(work: fullWork(), onTap: () {})));
      await tester.pump();

      final kinds = pillKinds(tester);
      expect(kinds['声优A'], OnlinePillKind.artist);
      expect(kinds['声优B'], OnlinePillKind.artist, reason: '多个声优要多个胶囊');
      expect(kinds['サークル'], OnlinePillKind.circle);
      expect(kinds['RJ01318014'], OnlinePillKind.rj);
      expect(kinds['2小时25分钟'], OnlinePillKind.duration);
      expect(kinds['↓1.2万'], OnlinePillKind.download);
      expect(tester.takeException(), isNull);
    });

    testWidgets('时长走「2小时25分钟」而不是钟表写法 2:25:00', (tester) async {
      await tester.pumpWidget(host(OnlineWorkCard(work: fullWork(), onTap: () {})));
      await tester.pump();

      expect(find.text('2小时25分钟'), findsOneWidget);
      expect(find.text('2:25:00'), findsNothing,
          reason: '两端同一个概念必须是同一种写法：本地卡面用的是 formatDuration');
    });

    testWidgets('取不到的几枚直接不出现（没 RJ号 / 时长为 0 / 下载量为 0）',
        (tester) async {
      await tester.pumpWidget(
        host(
          OnlineWorkCard(
            work: const OnlineWork(id: 1, title: '什么元数据都没有'),
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(OnlinePill), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('只有时长时只出现时长那一枚', (tester) async {
      await tester.pumpWidget(
        host(
          OnlineWorkCard(
            work: const OnlineWork(
              id: 2,
              title: '只有时长',
              durationSeconds: 45 * 60,
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pump();

      final kinds = pillKinds(tester);
      expect(kinds, {'45分钟': OnlinePillKind.duration});
    });

    testWidgets('在线卡片文字倍率由卡片自己读设置（倍率 1.5 → 标题 13×1.5）',
        (tester) async {
      const title = '一个标题';
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              (ref) => _StubSettings(const [], cardScale: 1.5),
            ),
          ],
          child: MaterialApp(
            theme: buildHikoTheme(const AppSettings()),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 200,
                  height: 900,
                  child: OnlineWorkCard(
                    work: const OnlineWork(id: 3, title: title),
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.widget<Text>(find.text(title)).style?.fontSize,
        closeTo(kOnlineCardTitleFontSize * 1.5, 0.001),
        reason: '网格不再传这个倍率，卡片必须自己从设置里读',
      );
    });

    test('六类胶囊（含标签）的取色互不相同，浅色 / 深色各一遍', () {
      for (final theme in ['light', 'dark']) {
        final isDark = theme == 'dark';
        final scheme = buildHikoTheme(AppSettings(theme: theme)).colorScheme;
        final fgs = <Color>[
          for (final kind in OnlinePillKind.values)
            onlinePillColors(kind, isDark: isDark, scheme: scheme).fg,
          // 第六类：标签胶囊的青色
          hikoTagFgColorOf(isDark),
        ];
        expect(
          fgs.toSet().length,
          fgs.length,
          reason: '$theme 主题下有两类胶囊字色撞了，卡面上就分不出来了',
        );

        final bgs = <Color>[
          for (final kind in OnlinePillKind.values)
            onlinePillColors(kind, isDark: isDark, scheme: scheme).bg,
        ];
        expect(
          bgs.toSet().length,
          bgs.length,
          reason: '$theme 主题下有两类胶囊底色撞了',
        );
      }
    });
  });

  group('瀑布流（1.99.21 取代固定高度的 SliverGrid）', () {
    Widget gridHost({
      required List<OnlineWork> works,
      bool isMobile = false,
      double gridColumns = 0,
      bool showTags = false,
      double width = 900,
      double height = 1400,
    }) =>
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              (ref) => _StubSettings(const [], gridColumns: gridColumns),
            ),
          ],
          child: MaterialApp(
            theme: buildHikoTheme(const AppSettings()),
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: height,
                child: OnlineWorkGrid(
                  works: works,
                  isMobile: isMobile,
                  showTags: showTags,
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        );

    List<Offset> cardOffsets(WidgetTester tester, int count) => [
          for (var i = 0; i < count; i++)
            tester.getTopLeft(find.byType(OnlineWorkCard).at(i)),
        ];

    testWidgets('卡片高度由内容决定：同一屏里出现不同高度', (tester) async {
      await tester.pumpWidget(
        gridHost(
          works: [
            // 长标题 + 一堆标签 = 高
            OnlineWork(
              id: 1,
              title: '这是一个足够长的标题，长到在 300px 宽的卡片里必然占满两行',
              tags: [
                for (final name in const ['双声道立体声/人头麦', '亲热/甜蜜', '青梅竹马'])
                  OnlineTag(id: 200, name: name),
              ],
            ),
            // 短标题、无标签 = 矮
            const OnlineWork(id: 2, title: '短'),
          ],
          gridColumns: 2,
          showTags: true,
          width: 600,
        ),
      );
      await tester.pump();

      final tall = tester.getSize(find.byType(OnlineWorkCard).at(0)).height;
      final short = tester.getSize(find.byType(OnlineWorkCard).at(1)).height;
      expect(tall, greaterThan(short + 20),
          reason: '等高网格会强行把两张卡拉成一样高，那就不是瀑布流了');
      expect(tester.takeException(), isNull);
    });

    testWidgets('第 3 张落在更矮的那一列下面（不是等高网格）', (tester) async {
      await tester.pumpWidget(
        gridHost(
          works: [
            OnlineWork(
              id: 1,
              title: '这是一个足够长的标题，长到在 300px 宽的卡片里必然占满两行',
              tags: [
                for (final name in const [
                  '双声道立体声/人头麦',
                  '亲热/甜蜜',
                  '青梅竹马',
                  '学生',
                ])
                  OnlineTag(id: 200, name: name),
              ],
            ),
            const OnlineWork(id: 2, title: '短'),
            const OnlineWork(id: 3, title: '第三张'),
          ],
          gridColumns: 2,
          showTags: true,
          width: 600,
        ),
      );
      await tester.pump();

      final p = cardOffsets(tester, 3);
      expect(p[2].dx, p[1].dx, reason: '第 1 张更高，第 3 张该补到第 2 列');
      expect(p[2].dy, greaterThan(p[1].dy));
    });

    testWidgets('自动档在 900 宽下是 3 列：第 4 张换行', (tester) async {
      await tester.pumpWidget(
        gridHost(
          works: [for (var i = 0; i < 6; i++) work(id: 1657200 + i)],
        ),
      );
      await tester.pump();

      final p = cardOffsets(tester, 6);
      expect(p[2].dy, p[0].dy);
      expect(p[3].dy, greaterThan(p[0].dy), reason: '自动档不是 4 列');
      expect(p[3].dx, p[0].dx);
    });

    testWidgets('每行卡片数固定 5 列时前 5 张同排', (tester) async {
      await tester.pumpWidget(
        gridHost(
          works: [for (var i = 0; i < 6; i++) work(id: 1657200 + i)],
          gridColumns: 5,
        ),
      );
      await tester.pump();

      final p = cardOffsets(tester, 6);
      expect(p[4].dy, p[0].dy, reason: '固定 5 列时前 5 张在同一排');
      expect(p[5].dy, greaterThan(p[0].dy), reason: '第 6 张才换行');
    });

    testWidgets('移动端 2 列，左右各留 16px', (tester) async {
      await tester.pumpWidget(
        gridHost(
          works: [for (var i = 0; i < 4; i++) work(id: 1657200 + i)],
          isMobile: true,
          width: 400,
        ),
      );
      await tester.pump();

      final p = cardOffsets(tester, 4);
      expect(p[0].dx, 16);
      expect(p[1].dx, greaterThan(p[0].dx));
      expect(p[2].dx, p[0].dx, reason: '第 3 张回到第 1 列');
      expect(p[2].dy, greaterThan(p[0].dy));
    });
  });
}

/// 固定黑名单 / 在线外观的 settings notifier：不读也不写 SharedPreferences
class _StubSettings extends SettingsNotifier {
  _StubSettings(
    List<OnlineTag> blocked, {
    double cardScale = 1.0,
    double gridColumns = 0,
  }) {
    state = state.copyWith(
      blockedTags: blocked,
      onlineCardTextScale: cardScale,
      onlineGridColumns: gridColumns,
    );
  }
}

/// 固定索引的收藏 notifier：不发起任何请求
class _StubFavorites extends OnlineFavoritesNotifier {
  _StubFavorites(super.ref, OnlineFavorites index) {
    state = OnlineFavoritesState(index: index);
  }
}

/// 记录封面请求但不联网的 HttpClient
class _RecordingHttpOverrides extends HttpOverrides {
  _RecordingHttpOverrides(this.requested);

  final List<Uri> requested;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingHttpClient(requested);
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this.requested);

  final List<Uri> requested;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    throw const SocketException('单测环境不联网');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
