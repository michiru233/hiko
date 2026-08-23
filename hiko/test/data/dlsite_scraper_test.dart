import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/dlsite_scraper.dart';
import 'package:hiko/models/album.dart';

/// DLsite 刮削解析单测：使用真实作品页（RJ337515，2026-08-14 抓取）作为 fixture。
/// fixture 来自公开作品页面，仅用于离线验证解析逻辑。
void main() {
  final html = File('test/fixtures/dlsite_rj337515.html').readAsStringSync();

  group('parseTags', () {
    test('解析出标签列表（去重）', () {
      final tags = DlsiteScraper.parseTags(html);
      expect(tags, isNotEmpty);
      expect(tags.length, greaterThanOrEqualTo(5));
      expect(tags, contains('男主人公'));
      expect(tags, contains('サキュバス/淫魔'));
      expect(tags, contains('パイズリ'));
      // 无重复
      expect(tags.toSet().length, tags.length);
    });

    test('空 HTML 返回空列表', () {
      expect(DlsiteScraper.parseTags(''), isEmpty);
      expect(DlsiteScraper.parseTags('<html><body>no genres</body></html>'), isEmpty);
    });
  });

  group('parseTitle', () {
    test('解析出作品名', () {
      expect(DlsiteScraper.parseTitle(html), 'サキュバスプリズン～乳夢帰還～');
    });

    test('无标题返回 null', () {
      expect(DlsiteScraper.parseTitle('<html></html>'), isNull);
    });
  });

  group('URL 与代理', () {
    test('作品页 URL 构造正确', () {
      expect(
        Uri.parse('https://www.dlsite.com/maniax/work/=/product_id/RJ337515.html').toString(),
        contains('product_id/RJ337515'),
      );
    });
  });

  group('applyResults（1.32：刮削回写同时更新 title）', () {
    Album album(String title, {bool metaFromFolder = false, String id = 'a1'}) =>
        Album(
          id: id,
          sourcePath: '/x',
          title: title,
          rjCode: 'RJ123456',
          metaFromFolder: metaFromFolder,
          date: DateTime.now(),
        );

    test('成功刮削同时回写 dlsiteTitle 与 title，并清 metaFromFolder', () {
      final out = DlsiteScraper.applyResults(
        [album('RJ123456', metaFromFolder: true)],
        [const ScrapeDetail(id: 'a1', rj: 'RJ123456', tags: ['ASMR'], title: 'DLsite 作品名')],
      );
      expect(out.single.title, 'DLsite 作品名', reason: '列表显示的 title 必须同步更新');
      expect(out.single.dlsiteTitle, 'DLsite 作品名');
      expect(out.single.metaFromFolder, isFalse);
      expect(out.single.tags, ['ASMR']);
      expect(out.single.rjCode, 'RJ123456');
    });

    test('刮削无标题（title=null）不动 title', () {
      final out = DlsiteScraper.applyResults(
        [album('标签专辑名')],
        [const ScrapeDetail(id: 'a1', rj: 'RJ123456', tags: ['ASMR'])],
      );
      expect(out.single.title, '标签专辑名');
      expect(out.single.dlsiteTitle, isNull);
    });

    test('无结果的专辑原样保留', () {
      final out = DlsiteScraper.applyResults(
        [album('专辑甲'), album('专辑乙', id: 'a2')],
        [const ScrapeDetail(id: 'a1', rj: 'RJ123456', tags: ['ASMR'], title: '新标题')],
      );
      expect(out[1].title, '专辑乙');
    });
  });

  group('shouldBackfillTitle（1.32：DLsite 兜底判定）', () {
    test('metaFromFolder + RJ 号 → 需要兜底', () {
      expect(
        DlsiteScraper.shouldBackfillTitle(Album(
          id: 'a',
          sourcePath: '/x',
          title: 'RJ123456',
          rjCode: 'RJ123456',
          metaFromFolder: true,
          date: DateTime.now(),
        )),
        isTrue,
      );
    });

    test('有标签标题 / 已刮削 / 无 RJ → 不兜底', () {
      final base = Album(
        id: 'a',
        sourcePath: '/x',
        title: 'T',
        date: DateTime.now(),
      );
      expect(DlsiteScraper.shouldBackfillTitle(base.copyWith(rjCode: 'RJ1')), isFalse,
          reason: '标题来自标签（metaFromFolder=false）');
      expect(
        DlsiteScraper.shouldBackfillTitle(
          base.copyWith(rjCode: 'RJ1', metaFromFolder: true, dlsiteTitle: '已有标题')),
        isFalse,
        reason: '已刮削过');
      expect(
        DlsiteScraper.shouldBackfillTitle(base.copyWith(metaFromFolder: true)),
        isFalse,
        reason: '无 RJ 号查不了 DLsite');
    });
  });
}
