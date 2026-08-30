import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/album_card.dart';
import 'package:hiko/utils/time.dart';

/// 1.42.0 专辑卡片五项信息：专辑名/艺术家/专辑艺术家/RJ号/总时长
/// 全部可见、无溢出裁切；albumArtist 与 artist 去重。
/// 1.43.0 刮削标签开关：卡片经 showScrapedTags 参数控制 tags 渲染
/// （卡片不读 ProviderScope，保持可独立构造，widget_test 依赖这一点）。
void main() {
  Widget host(
    Album album, {
    bool showScrapedTags = false,
    String themeName = 'light',
  }) {
    return MaterialApp(
      theme: buildHikoTheme(AppSettings(theme: themeName)),
      home: Align(
        alignment: Alignment.topLeft,
        // 桌面网格单卡实际尺寸：宽 190、高 190/0.60（home_screen 网格参数）
        child: SizedBox(
          width: 190,
          height: 190 / 0.60,
          child: AlbumCard(
            album: album,
            multiMode: false,
            selected: false,
            showScrapedTags: showScrapedTags,
            onTap: () {},
            onContextMenu: null,
          ),
        ),
      ),
    );
  }

  Album fullAlbum() => Album(
        id: 'local-test1',
        sourcePath: '/tmp/rj123',
        title: '夜のひめごと',
        artist: '声優A',
        albumArtist: 'サークルB',
        rjCode: 'RJ01234567',
        genre: '癒し',
        totalDuration: 5025,
        duration: 8,
        tags: const ['耳かき', '寝落ち', 'オールナイト'],
        date: DateTime(2026),
      );

  testWidgets('五项信息全部渲染：标题/艺术家/RJ号/总时长，无溢出', (tester) async {
    await tester.pumpWidget(host(fullAlbum()));
    await tester.pump();
    expect(find.text('夜のひめごと'), findsOneWidget);
    // 1.44：artist/albumArtist 各为一颗胶囊，不再是合并文本行
    expect(find.text('声優A'), findsOneWidget);
    expect(find.text('サークルB'), findsOneWidget);
    expect(find.text('声優A · サークルB'), findsNothing);
    expect(find.text('RJ01234567'), findsOneWidget);
    expect(find.text(formatDuration(5025)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1.44 超长艺术家名：胶囊内省略号截断，无溢出', (tester) async {
    final longName = '超長いアーティスト名前' * 6; // 60 字
    final album = fullAlbum().copyWith(
      artist: longName,
      albumArtist: '別のサークル名もかなり長い名前です' * 2,
    );
    await tester.pumpWidget(host(album));
    await tester.pump();
    expect(find.textContaining('超長い'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '超长艺术家名在 190px 卡片内必须省略号截断而非溢出');
  });

  testWidgets('albumArtist 与 artist 相同时去重：艺术家文本只出现一次', (tester) async {
    final album = fullAlbum().copyWith(albumArtist: '声優A');
    await tester.pumpWidget(host(album));
    await tester.pump();
    expect(find.text('声優A'), findsOneWidget);
    expect(find.text('声優A · 声優A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('albumArtist 为空时只显示 artist，不出现悬空分隔符', (tester) async {
    final album = fullAlbum().copyWith(albumArtist: '');
    await tester.pumpWidget(host(album));
    await tester.pump();
    expect(find.text('声優A'), findsOneWidget);
    expect(find.text('声優A · '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无 RJ 号显示「本地导入」，totalDuration 为 0 回退曲目数', (tester) async {
    final album = Album(
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
    await tester.pumpWidget(host(album));
    await tester.pump();
    expect(find.text('本地导入'), findsOneWidget);
    expect(find.text('8 首'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('浅色与深色主题下都无溢出', (tester) async {
    for (final themeName in ['light', 'dark']) {
      await tester.pumpWidget(host(fullAlbum(), themeName: themeName));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: '$themeName 主题下卡片溢出');
    }
  });

  testWidgets('1.43 刮削标签开关：关不渲染 tags，开=渲染（两态均无溢出）',
      (tester) async {
    // 默认（关）→ tags 不渲染
    await tester.pumpWidget(host(fullAlbum()));
    await tester.pump();
    expect(find.text('耳かき'), findsNothing, reason: '刮削标签默认隐藏');
    expect(tester.takeException(), isNull);

    // 开 → tags 渲染
    await tester.pumpWidget(host(fullAlbum(), showScrapedTags: true));
    await tester.pump();
    expect(find.text('耳かき'), findsOneWidget, reason: '开关打开后显示刮削标签');
    expect(find.text('寝落ち'), findsOneWidget);
    expect(find.text('オールナイト'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
