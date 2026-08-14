import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru/data/dlsite_scraper.dart';
import 'package:kikoeru/data/library_store.dart';
import 'package:kikoeru/data/settings_store.dart';
import 'package:kikoeru/models/album.dart';

/// 实网刮削端到端验证：需要能访问 DLsite（本机代理 127.0.0.1:7890）。
/// 默认跳过：KIKOERU_NETWORK_TESTS=1 flutter test test/data/dlsite_scraper_network_test.dart
void main() {
  test('真实 DLsite 页面刮削（RJ337515）', () async {
    if (Platform.environment['KIKOERU_NETWORK_TESTS'] != '1') {
      markTestSkipped('实网测试默认跳过：KIKOERU_NETWORK_TESTS=1 启用');
      return;
    }
    final tmp = Directory.systemTemp.createTempSync('kikoeru-scrape');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = LibraryStore(overrideDir: tmp);
    final album = Album(
      id: 'local-net',
      sourcePath: '/x/RJ337515_サキュバスプリズン',
      title: 'サキュバスプリズン～乳夢帰還～',
      date: DateTime.now(),
      tracks: [],
    );
    await store.save([album]);

    final scraper = DlsiteScraper(
        store, () => const AppSettings(scrapeProxy: 'http://127.0.0.1:7890'));
    final result = await scraper.scrape({'local-net'}, force: true);

    expect(result.scraped, 1);
    expect(result.failed, 0);
    expect(result.details.single.tags, isNotEmpty);
    expect(result.details.single.title, 'サキュバスプリズン～乳夢帰還～');

    // 落盘检查
    final saved = await store.load();
    expect(saved.single.tags, isNotEmpty);
    expect(saved.single.dlsiteTitle, 'サキュバスプリズン～乳夢帰還～');
  });
}
