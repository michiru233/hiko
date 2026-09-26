import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/online/online_favorites.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/screens/online_screen.dart';
import 'package:hiko/ui/theme.dart';

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

  OnlineWork work({int id = 1657200}) =>
      OnlineWork(id: id, title: '测试作品', circleName: 'サークル');

  Widget host(Widget child) => ProviderScope(
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
