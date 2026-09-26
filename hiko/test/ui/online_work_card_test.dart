import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/online/online_favorites.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/screens/online_screen.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/detail_kit.dart';
import 'package:hiko/ui/widgets/online_cover.dart';
import 'package:hiko/ui/widgets/online_work_grid.dart';

/// 1.93.0：在线列表卡片的两件事 ——
/// ① 封面必须取**原图**（主界面封面模糊的全部原因就是这里拿了 240×180 缩略图，
///    卡片在 Retina 上需要 400–520 物理像素，等于放大 2.4–2.9 倍）；
/// ② 收藏角标跟着歌单索引走。
///
/// ①的断言方式是拦下真实的 HTTP 请求看它请求了哪个 URL ——
/// 「卡片用了什么图」只有这一种不依赖实现细节的验证办法。
void main() {
  // 拦下所有封面请求：单测不该联网，也不该留下待处理的连接定时器
  late List<Uri> requested;

  setUp(() {
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

  /// [height] 默认 = 「封面正方形 + 两行标题 + 一行副标题」（200 + 62）。
  /// 开了标签行要自己加 24（= kOnlineCardTagRow），否则卡片内部会溢出。
  Widget host(Widget child, {double width = 200, double height = 262}) =>
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
              child: SizedBox(width: 200, height: 262, child: child),
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
  group('卡面标签行（1.94.0）', () {
    // 200px 宽卡片、开标签行 → 高度要多留 24（与 kOnlineCardTagRow 对齐）
    Widget tagHost(
      Widget child, {
      double width = 200,
      double height = 286,
    }) =>
        host(child, width: width, height: height);

    testWidgets('开关关闭时不渲染任何标签', (tester) async {
      await tester.pumpWidget(
        tagHost(
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

    testWidgets('放得下就全显示，不出现 +N', (tester) async {
      await tester.pumpWidget(
        tagHost(
          OnlineWorkCard(
            work: tagged(['ASMR', '治愈']),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ASMR'), findsOneWidget);
      expect(find.text('治愈'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('放不下时截断并给出 +N，且 +N 显示的是被藏起来的个数', (tester) async {
      await tester.pumpWidget(
        tagHost(
          OnlineWorkCard(
            work: tagged([
              '双声道立体声/人头麦',
              '亲热/甜蜜',
              '青梅竹马',
              '学生',
              'ASMR',
            ]),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
        ),
      );
      await tester.pump();
      // 至少有一个 `+N`，且不是「+5」这种总数写法
      expect(find.textContaining('+'), findsOneWidget);
      final more = tester.widget<Text>(find.textContaining('+')).data!;
      final hidden = int.parse(more.substring(1));
      expect(hidden, greaterThan(0));
      expect(hidden, lessThan(5), reason: '宽卡片至少该放得下 1 个标签');
      expect(tester.takeException(), isNull, reason: '单行截断不该溢出');
    });

    testWidgets('点标签只触发筛选，不会连带打开详情', (tester) async {
      OnlineTag? tapped;
      var cardTaps = 0;
      await tester.pumpWidget(
        tagHost(
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

    testWidgets('点 +N 等于打开详情看全部标签', (tester) async {
      var cardTaps = 0;
      await tester.pumpWidget(
        tagHost(
          OnlineWorkCard(
            // 用长标签名，确保一定放不下、出现 `+N`
            work: tagged([
              '双声道立体声/人头麦',
              '亲热/甜蜜',
              '青梅竹马',
              '学生',
            ]),
            onTap: () => cardTaps++,
            showTags: true,
            onTagTap: (_) {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.textContaining('+'));
      await tester.pump();

      expect(cardTaps, 1, reason: '`+N` 与卡片同义：打开详情');
    });

    testWidgets('服务端只给了名字（id=0）的标签只能看，点了不筛选', (tester) async {
      var tagTaps = 0;
      await tester.pumpWidget(
        tagHost(
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

    testWidgets('窄卡片（移动端 2 列）也保持单行不溢出', (tester) async {
      await tester.pumpWidget(
        tagHost(
          OnlineWorkCard(
            work: tagged([
              '双声道立体声/人头麦',
              '亲热/甜蜜',
              '青梅竹马',
              '学生',
              '环绕音',
            ]),
            onTap: () {},
            showTags: true,
            onTagTap: (_) {},
          ),
          width: 150,
          height: 236,
        ),
      );
      await tester.pump();
      expect(find.textContaining('+'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '窄卡片不能溢出');
    });
  });

  group('卡面标签：黑名单与菜单（1.95.0）', () {
    Widget hostWith(
      Widget card, {
      List<OnlineTag> blocked = const [],
      double scale = 1.0,
      double width = 200,
      double height = 286,
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
                child: SizedBox(width: width, height: height, child: card),
              ),
            ),
          ),
        );

    testWidgets('全局字号放大到 1.30 时标签行仍不溢出（1.95.0 修的量宽漏 textScaler）',
        (tester) async {
      await tester.pumpWidget(
        hostWith(
          OnlineWorkCard(
            // 第二个标签刻意取**窄**的：「第一个放得下、第二个放不下」这种
            // 临界排布下，量宽的富余最小，漏 scaler 的后果才会真的溢出屏幕
            // （实测漏掉时溢出 36px；换成更宽的第二个标签就碰巧被富余吃掉）
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

      // 量宽度时若漏掉 `MediaQuery.textScaler`，就是「量 9pt、画 11.7pt」——
      // 标签行当场溢出卡片。这条锁在 1.95.0 之前是红的（RenderFlex overflowed）。
      expect(
        tester.takeException(),
        isNull,
        reason: '字号放大后标签行不该溢出：量的和画的必须是同一个 scaler',
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

  group('卡片尺寸预算（1.96.0）', () {
    /// 高度预算算对没有，看的是**封面高度与宽度之差**。
    ///
    /// 为什么不直接断言「封面是正方形」：**它本来就不是**。卡片 `Container` 的
    /// 4px 内边距在文字块预算里被当成余量补掉了（1.95.0 的硬编码 62 就是这么来的），
    /// 所以封面的高度恒定地比宽度多 `kOnlineCardPadding * 2` —— 这是既有观感，
    /// 1.96.0 不打算顺手改掉它。
    ///
    /// 这个差值**与所有字号旋钮无关**，所以它可以当锁：只要高度预算漏算了任何一项
    /// （在线卡片倍率 / 全局字号 / 标签字号），差值就会变 —— 差值变小 = 封面被压扁。
    ///
    /// 为什么不用「有没有 RenderFlex 溢出」当锁：封面外面那层 `Expanded` 会一直
    /// 吞到 0 高度，它永远不会溢出、永远不报错。
    ///
    /// 标题必须**长到占满两行**：一行标题会让 `Expanded` 多拿一行高度，
    /// 差值随之变大（这是既有的、与字号无关的行为）。
    const longTitle = '这是一个足够长的在线作品标题，用来确保它在卡片里确实占据两行高度';
    const overshoot = kOnlineCardPadding * 2;

    Widget gridHost({
      required double cardScale,
      required double globalScale,
      double tagFontSize = 11,
      double gridColumns = 0,
      bool showTags = true,
      int count = 3,
      double width = 900,
      double height = 700,
    }) =>
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              (ref) => _StubSettings(
                const [],
                cardScale: cardScale,
                gridColumns: gridColumns,
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildHikoTheme(const AppSettings()),
            builder: (context, inner) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(globalScale),
              ),
              child: HikoTagFontScope(fontSize: tagFontSize, child: inner!),
            ),
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: height,
                child: OnlineWorkGrid(
                  works: [
                    for (var i = 0; i < count; i++)
                      work(id: 1657200 + i, title: longTitle),
                  ],
                  isMobile: false,
                  showTags: showTags,
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        );

    double coverOvershoot(WidgetTester tester) {
      final cover = tester.getSize(find.byType(OnlineCover).first);
      return cover.height - cover.width;
    }

    testWidgets('默认档位：封面高度与宽度之差就是那 8px 余量', (tester) async {
      await tester.pumpWidget(gridHost(cardScale: 1.0, globalScale: 1.0));
      await tester.pump();

      expect(coverOvershoot(tester), closeTo(overshoot, 1.0),
          reason: '与 1.95.0 的默认观感保持一致：封面比宽度高 8px');
      expect(tester.takeException(), isNull);
    });

    testWidgets('卡片文字 1.30× + 全局字号 1.30：差值不变（高度预算必须联动）',
        (tester) async {
      await tester.pumpWidget(gridHost(cardScale: 1.3, globalScale: 1.3));
      await tester.pump();

      expect(coverOvershoot(tester), closeTo(overshoot, 1.0),
          reason: '两个缩放旋钮都必须进高度预算，只算一个封面就会被压扁');
      expect(tester.takeException(), isNull);
    });

    testWidgets('只放大在线卡片文字（全局字号不变）时差值也不变', (tester) async {
      await tester.pumpWidget(gridHost(cardScale: 1.3, globalScale: 1.0));
      await tester.pump();
      expect(coverOvershoot(tester), closeTo(overshoot, 1.0));
    });

    testWidgets('标签字号 14：标签行高度跟着涨，差值仍不变', (tester) async {
      await tester.pumpWidget(
        gridHost(cardScale: 1.0, globalScale: 1.0, tagFontSize: 14),
      );
      await tester.pump();

      expect(coverOvershoot(tester), closeTo(overshoot, 1.0),
          reason: '标签胶囊走的是绝对字号，它变高时标签行预算必须一起变');
      expect(tester.takeException(), isNull);
    });

    testWidgets('关掉标签行时不留那块空高', (tester) async {
      await tester.pumpWidget(
        gridHost(cardScale: 1.0, globalScale: 1.0, showTags: false),
      );
      await tester.pump();

      expect(coverOvershoot(tester), closeTo(overshoot, 1.0));
    });

    testWidgets('自动档在 900 宽下是 3 列：第 4 张换行', (tester) async {
      await tester.pumpWidget(
        gridHost(cardScale: 1.0, globalScale: 1.0, count: 6),
      );
      await tester.pump();

      final positions = [
        for (var i = 0; i < 6; i++)
          tester.getTopLeft(find.byType(OnlineWorkCard).at(i)),
      ];
      expect(positions[2].dy, positions[0].dy);
      expect(positions[3].dy, greaterThan(positions[0].dy), reason: '自动档不是 5 列');
    });

    testWidgets('每行卡片数固定 5 列时前 5 张同排', (tester) async {
      await tester.pumpWidget(
        gridHost(
          cardScale: 1.0,
          globalScale: 1.0,
          gridColumns: 5,
          count: 6,
        ),
      );
      await tester.pump();

      final positions = [
        for (var i = 0; i < 6; i++)
          tester.getTopLeft(find.byType(OnlineWorkCard).at(i)),
      ];
      expect(positions[4].dy, positions[0].dy, reason: '固定 5 列时前 5 张在同一排');
      expect(positions[5].dy, greaterThan(positions[0].dy), reason: '第 6 张才换行');
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
