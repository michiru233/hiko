import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/utils/grid_locate.dart';

Album _album(String id) =>
    Album(id: id, sourcePath: '', title: id, date: DateTime(2026));

List<Album> _library(int count) =>
    List.generate(count, (i) => _album('rj${i.toString().padLeft(3, '0')}'));

void main() {
  group('locateAlbumInGrid（1.49 定位当前播放）', () {
    // 公共基准：crossExtent=1096-96=1000；Fixed 5 列 → 卡宽 (1000-4×18)/5=185.6，
    // 卡高=185.6/0.5=371.2，行距 25 → 行Stride 396.2；顶部 padding 16。
    final fixed = GridMetrics(
      useFixedCount: true,
      fixedCrossAxisCount: 5,
      childAspectRatio: 0.5,
      viewportWidth: 1096,
      horizontalPadding: 96,
      topPadding: 16,
    );

    test('Fixed 列数：索引 12 → 第 3 行，偏移 16+2×396.2=808.4', () {
      final r = locateAlbumInGrid(
          filtered: _library(20), albumId: 'rj012', metrics: fixed);
      expect(r.found, isTrue);
      expect(r.index, 12);
      expect(r.columns, 5);
      expect(r.scrollOffset, closeTo(808.4, 0.01));
    });

    test('MaxExtent 列数按 ceil：1000 宽、上限 191 → 5 列（floor 会错算 4）', () {
      // ceil(1000/209)=5 → 卡宽 (1000-4×18)/5=185.6；索引 7 → 第 2 行
      final r = locateAlbumInGrid(
        filtered: _library(20),
        albumId: 'rj007',
        metrics: GridMetrics(
          useFixedCount: false,
          maxCrossAxisExtent: 191,
          childAspectRatio: 0.5,
          viewportWidth: 1096,
          horizontalPadding: 96,
          topPadding: 16,
        ),
      );
      expect(r.found, isTrue);
      expect(r.columns, 5);
      expect(r.scrollOffset, closeTo(412.2, 0.01));
    });

    test('目标不在列表：found=false、index=-1、偏移 0，但仍给出列数', () {
      final r = locateAlbumInGrid(
          filtered: _library(10), albumId: 'nope', metrics: fixed);
      expect(r.found, isFalse);
      expect(r.index, -1);
      expect(r.scrollOffset, 0);
      expect(r.columns, 5);
    });

    test('窄视口至少 1 列；首个元素偏移＝顶部 padding', () {
      final r = locateAlbumInGrid(
        filtered: _library(3),
        albumId: 'rj000',
        metrics: GridMetrics(
          useFixedCount: false,
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.6,
          viewportWidth: 50,
          topPadding: 16,
        ),
      );
      expect(r.columns, 1);
      expect(r.scrollOffset, 16);
    });

    test('列数越多行号越小：同专辑 Fixed 10 列下索引 12 → 第 2 行', () {
      final r = locateAlbumInGrid(
        filtered: _library(20),
        albumId: 'rj012',
        metrics: GridMetrics(
          useFixedCount: true,
          fixedCrossAxisCount: 10,
          childAspectRatio: 0.5,
          viewportWidth: 1096,
          horizontalPadding: 96,
          topPadding: 16,
        ),
      );
      // 卡宽 (1000-9×18)/10=83.8 → 卡高 167.6 → 行Stride 192.6；row=1
      expect(r.columns, 10);
      expect(r.scrollOffset, closeTo(16 + 192.6, 0.01));
    });
  });
}
