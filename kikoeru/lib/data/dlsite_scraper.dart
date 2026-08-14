import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/album.dart';
import '../utils/rj.dart';
import 'library_provider.dart';
import 'library_store.dart';
import 'settings_store.dart';

/// 单张刮削结果
class ScrapeDetail {
  final String id;
  final String rj;
  final List<String>? tags;
  final String? title;
  final String? error;

  const ScrapeDetail({required this.id, required this.rj, this.tags, this.title, this.error});
}

/// 批量刮削汇总
class ScrapeResult {
  final int scraped;
  final int failed;
  final int skipped;
  final int noRj;
  final List<ScrapeDetail> details;

  const ScrapeResult({
    required this.scraped,
    required this.failed,
    required this.skipped,
    required this.noRj,
    required this.details,
  });
}

/// DLsite 标签刮削（移植旧版 main.js dlsite:scrape + DlsiteScraper.kt）：
/// 原生网络栈无 CORS；400ms 限速；已刮过默认跳过；代理支持。
class DlsiteScraper {
  DlsiteScraper(this._store, this._settingsRef);

  final LibraryStore _store;
  final AppSettings Function() _settingsRef;

  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36';
  static final _tagRegex = RegExp(
    r'genre/\d+/from/work\.genre/ana_flg/all"[^>]*>([^<]+)</a>',
    caseSensitive: false,
  );

  Future<ScrapeResult> scrape(
    Set<String> ids, {
    required bool force,
    void Function(int processed, int total)? onProgress,
  }) async {
    final albums = await _store.load();
    final targets = <Album>[];
    var noRj = 0;
    for (final album in albums) {
      if (!ids.contains(album.id)) continue;
      final rj = albumRjCode(album);
      if (rj == null) {
        noRj++;
        continue;
      }
      targets.add(album.copyWith(rjCode: rj));
    }

    final results = <ScrapeDetail>[];
    var scraped = 0, failed = 0, skipped = 0;
    final proxy = _settingsRef().scrapeProxy;
    var processed = 0;

    for (final album in targets) {
      processed++;
      onProgress?.call(processed, targets.length);
      if (!force && album.tags.isNotEmpty) {
        skipped++;
        continue;
      }
      try {
        final html = await _fetch(album.rjCode!, proxy);
        final tags = _parseTags(html);
        final title = _parseTitle(html);
        results.add(ScrapeDetail(id: album.id, rj: album.rjCode!, tags: tags, title: title));
        if (tags.isNotEmpty) {
          scraped++;
        } else {
          failed++;
        }
      } catch (e) {
        failed++;
        results.add(ScrapeDetail(id: album.id, rj: album.rjCode!, error: e.toString()));
      }
      await Future.delayed(const Duration(milliseconds: 400)); // 礼貌限速
    }

    // 回写刮削结果并落盘
    if (results.isNotEmpty || noRj > 0) {
      final byId = {for (final d in results) d.id: d};
      final updated = [
        for (final a in albums)
          byId.containsKey(a.id)
              ? a.copyWith(
                  rjCode: byId[a.id]!.rj,
                  tags: byId[a.id]!.tags ?? a.tags,
                  dlsiteTitle: byId[a.id]!.title ?? a.dlsiteTitle,
                )
              : a,
      ];
      await _store.save(updated);
    }

    return ScrapeResult(
      scraped: scraped,
      failed: failed,
      skipped: skipped,
      noRj: noRj,
      details: results,
    );
  }

  Future<String> _fetch(String rj, String proxy) async {
    final url = 'https://www.dlsite.com/maniax/work/=/product_id/$rj.html';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = _ua;
    if (proxy.isNotEmpty) {
      final uri = Uri.tryParse(proxy);
      if (uri != null && uri.host.isNotEmpty) {
        client.findProxy = (_) => 'PROXY ${uri.host}:${uri.port}';
      }
    }
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Accept-Language', 'ja,zh-CN;q=0.8');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('DLsite 返回 ${response.statusCode}', uri: Uri.parse(url));
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  List<String> _parseTags(String html) {
    final tags = <String>[];
    for (final m in _tagRegex.allMatches(html)) {
      final tag = m.group(1)!.trim();
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
    }
    return tags;
  }

  String? _parseTitle(String html) {
    final match = RegExp(r'id="work_name"[^>]*>([^<]+)<').firstMatch(html);
    return match?.group(1)?.trim();
  }
}

final scraperProvider = Provider<DlsiteScraper>((ref) {
  return DlsiteScraper(ref.watch(libraryStoreProvider), () => ref.read(settingsProvider));
});
