import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/screens/home_screen.dart';
import 'package:hiko/ui/widgets/album_card.dart';

/// 1.49「定位当前播放」：按钮置灰/可点、点击后网格定位+高亮、卡片高亮参数。
/// 播放状态用真实 PlaybackController 直接置 state（构造无副作用，实测可跑），
/// 库数据用 LibraryNotifier 精确子类播种（LibraryStore 构造纯内存）。

class _SeededLibrary extends LibraryNotifier {
  _SeededLibrary(List<Album> albums) : super(LibraryStore()) {
    state = albums;
  }
}

Album _album(String id) => Album(
      id: id,
      sourcePath: '/x/$id',
      title: id,
      date: DateTime(2026),
      tracks: [Track(index: 0, name: 'n', url: 'file:///$id.mp3')],
    );

List<Album> _library(int count) =>
    List.generate(count, (i) => _album('rj${i.toString().padLeft(3, '0')}'));

final Finder locateButton = find.ancestor(
  of: find.byTooltip('定位当前播放'),
  matching: find.byType(IconButton),
);

final Finder glowCard = find.byWidgetPredicate(
  (w) =>
      w is AnimatedContainer &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).border != null,
);

void main() {
  // 用应用默认窗口尺寸（1440×920）：800×600 默认画布下顶栏/播放条会溢出报渲染异常
  Future<void> useDesktopSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('无播放时「定位当前播放」按钮置灰（onPressed 为 null）', (tester) async {
    await useDesktopSurface(tester);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: HomeScreen()),
    ));
    // 等 initState 的 500ms 延迟扫描计时器走完（空目录即返，无 IO）
    await tester.pump(const Duration(milliseconds: 600));
    expect(locateButton, findsOneWidget);
    expect(tester.widget<IconButton>(locateButton).onPressed, isNull);
  });

  testWidgets('播放中点击：网格定位到目标卡并短暂发光，约 2 秒后熄灭', (tester) async {
    await useDesktopSurface(tester);
    final albums = _library(30);
    final target = albums[29]; // 默认 3 列布局下第 10 行，必然需要滚动
    await tester.pumpWidget(ProviderScope(
      overrides: [
        libraryProvider.overrideWith((ref) => _SeededLibrary(albums)),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.widget<IconButton>(locateButton).onPressed, isNull);

    // 用真实控制器置播放状态（不触媒体通道），按钮转为可点
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    container.read(playbackProvider.notifier).state = PlaybackState(
      album: target,
      queue: target.tracks,
      queueIndex: 0,
      playing: true,
      position: 10,
      duration: 100,
    );
    await tester.pump();
    expect(tester.widget<IconButton>(locateButton).onPressed, isNotNull);
    expect(glowCard, findsNothing);

    await tester.tap(locateButton);
    await tester.pump(); // 布局帧 → postFrame 计算并 jumpTo
    await tester.pump(); // 新位置构建帧 → postFrame 点亮高亮
    await tester.pump(const Duration(milliseconds: 300));
    expect(glowCard, findsOneWidget);

    // 高亮 2 秒后自动熄灭
    await tester.pump(const Duration(seconds: 2, milliseconds: 400));
    expect(glowCard, findsNothing);
  });

  testWidgets('AlbumCard highlighted=true 渲染描边高亮，false 无高亮', (tester) async {
    Widget card(bool highlighted) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                height: 400,
                child: AlbumCard(
                  album: _album('hl'),
                  multiMode: false,
                  selected: false,
                  onTap: () {},
                  onContextMenu: null,
                  highlighted: highlighted,
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(card(true));
    await tester.pump();
    expect(glowCard, findsOneWidget);
    await tester.pumpWidget(card(false));
    await tester.pump();
    expect(glowCard, findsNothing);
  });
}
