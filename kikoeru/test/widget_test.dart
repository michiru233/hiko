import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru/models/album.dart';
import 'package:kikoeru/models/track.dart';
import 'package:kikoeru/ui/covers/cover_art.dart';

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
}
