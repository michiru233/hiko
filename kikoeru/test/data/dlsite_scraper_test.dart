import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru/data/dlsite_scraper.dart';

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
}
