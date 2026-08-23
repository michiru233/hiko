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
  static final _titleRegex = RegExp(r'id="work_name"[^>]*>([^<]+)<');

  /// 解析作品页标签（对应旧版 parseDlsiteTags）
  static List<String> parseTags(String html) {
    final tags = <String>[];
    for (final m in _tagRegex.allMatches(html)) {
      final tag = m.group(1)!.trim();
      if (tag.isNotEmpty && !tags.contains(tag)) tags.add(tag);
    }
    return tags;
  }

  /// 解析作品页标题（对应旧版 parseDlsiteTitle）
  static String? parseTitle(String html) {
    final match = _titleRegex.firstMatch(html);
    return match?.group(1)?.trim();
  }

  /// 是否需要 DLsite 兜底补标题：标题来自文件夹回退（全轨无可用标签）+ 有 RJ 号 + 尚未刮削
  static bool shouldBackfillTitle(Album a) =>
      a.metaFromFolder &&
      a.rjCode != null &&
      a.rjCode!.isNotEmpty &&
      (a.dlsiteTitle == null || a.dlsiteTitle!.isEmpty);

  /// 把刮削结果应用到专辑列表（纯函数，便于离线测试）：
  /// 刮到标题时同时回写 dlsiteTitle 与 title（列表显示立即更新）并清掉文件夹回退标记。
  static List<Album> applyResults(List<Album> albums, List<ScrapeDetail> results) {
    final byId = {for (final d in results) d.id: d};
    return [
      for (final a in albums)
        byId.containsKey(a.id)
            ? a.copyWith(
                rjCode: byId[a.id]!.rj,
                tags: byId[a.id]!.tags ?? a.tags,
                dlsiteTitle: byId[a.id]!.title ?? a.dlsiteTitle,
                title: byId[a.id]!.title ?? a.title,
                metaFromFolder: byId[a.id]!.title != null ? false : null,
              )
            : a,
    ];
  }

  /// 兜底补标题：全轨无可用标签（metaFromFolder）且能提取 RJ 号的专辑，
  /// 串行查询 DLsite 作品页标题回写 title + dlsiteTitle（领导定调的兜底路径）。
  /// 沿用 400ms 限速；连续 3 次网络异常提前结束本轮（离线时不拖垮导入）；
  /// DLsite 也失败则维持文件夹名，不算失败。返回补到标题的专辑数。
  Future<int> backfillTitles(List<Album> albums) async {
    final targets = albums.where(shouldBackfillTitle).toList();
    if (targets.isEmpty) return 0;

    final proxy = _settingsRef().scrapeProxy;
    final byId = {for (final a in albums) a.id: a};
    var fixed = 0;
    var consecutiveErrors = 0;
    for (final album in targets) {
      try {
        final html = await _fetch(album.rjCode!, proxy);
        final title = DlsiteScraper.parseTitle(html);
        if (title != null && title.isNotEmpty) {
          byId[album.id] = album.copyWith(
            title: title,
            dlsiteTitle: title,
            metaFromFolder: false,
          );
          fixed++;
        }
        consecutiveErrors = 0;
      } catch (_) {
        // 单张失败维持文件夹名；连续失败视为离线，跳过剩余
        consecutiveErrors++;
        if (consecutiveErrors >= 3) break;
      }
      await Future.delayed(const Duration(milliseconds: 400)); // 礼貌限速
    }
    if (fixed > 0) {
      await _store.save([for (final a in albums) byId[a.id] ?? a]);
    }
    return fixed;
  }

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
        final tags = DlsiteScraper.parseTags(html);
        final title = DlsiteScraper.parseTitle(html);
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

    // 回写刮削结果并落盘（title 同步更新，列表显示立即生效）
    if (results.isNotEmpty || noRj > 0) {
      final updated = DlsiteScraper.applyResults(albums, results);
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
}

final scraperProvider = Provider<DlsiteScraper>((ref) {
  return DlsiteScraper(ref.watch(libraryStoreProvider), () => ref.read(settingsProvider));
});
