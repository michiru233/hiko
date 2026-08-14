import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/ui/covers/cover_art.dart';
import 'package:hiko/ui/widgets/album_card.dart';

void main() {
  testWidgets('AlbumCover 无封面时渲染 SVG 兜底', (tester) async {
    final album = Album(
      id: 'local-test',
      sourcePath: '/x',
      title: '测试',
      date: DateTime.now(),
      tracks: [Track(index: 0, name: 't', url: 'file:///t.mp3')],
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(width: 100, height: 100, child: AlbumCover(album: album)),
      ),
    );
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('专辑卡片悬停显示点击指针', (tester) async {
    final album = Album(
      id: 'local-hover',
      sourcePath: '/x',
      title: '悬停测试',
      date: DateTime.now(),
      tracks: [Track(index: 0, name: 't', url: 'file:///t.mp3')],
    );
    MouseRegion? found;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 500,
              child: AlbumCard(
                album: album,
                multiMode: false,
                selected: false,
                onTap: () {},
                onContextMenu: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    // AlbumCard 应包 click cursor 的 MouseRegion（排除框架内部的 basic cursor）
    final clickable = find.byWidgetPredicate(
      (w) => w is MouseRegion && w.cursor == SystemMouseCursors.click,
    );
    expect(clickable, findsWidgets);
  });
}
