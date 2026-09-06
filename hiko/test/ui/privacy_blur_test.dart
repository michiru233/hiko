import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/covers/cover_art.dart';

/// 1.52 防社死隐私模糊：privacyBlur 默认开启，AlbumCover 整体被 ImageFiltered
/// 高斯模糊包装；关闭后恢复原图。全局 ValueNotifier 状态在用例间复位。
void main() {
  setUp(() => privacyBlur.value = true);

  Album album() => Album(
    id: 'local-test1',
    sourcePath: '/tmp/rj123',
    title: '夜のひめごと',
    artist: '声優A',
    albumArtist: 'サークルB',
    rjCode: null,
    genre: '癒し',
    totalDuration: 0,
    duration: 8,
    date: DateTime(2026),
  );

  Future<void> pumpCover(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: AlbumCover(album: album()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('默认模糊：封面被 ImageFiltered 包装（含 SVG 兜底封面）', (tester) async {
    await pumpCover(tester);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('关闭模糊：ImageFiltered 移除，封面原图直出；再开恢复', (tester) async {
    await pumpCover(tester);
    privacyBlur.value = false;
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing);

    privacyBlur.value = true;
    await tester.pump();
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('模糊不影响封面组件的其他部分（无异常抛出）', (tester) async {
    await pumpCover(tester);
    expect(tester.takeException(), isNull);
  });
}
