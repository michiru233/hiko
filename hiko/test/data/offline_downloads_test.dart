import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/online_audio_cache.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/offline_downloads.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:path/path.dart' as p;


Directory _tmpDir() =>
    Directory.systemTemp.createTempSync('hiko-offline-test-');

OnlineTrack _track(int workId, int fileId,
        {int size = 1024, String? lyricsHash}) =>
    OnlineTrack(
      hash: '$workId/$fileId',
      title: '音轨$fileId',
      type: 'audio',
      size: size,
      duration: 60,
      relativePath: '子目录',
      lyricsHash: lyricsHash,
    );

void main() {
  // 不设 TestWidgetsFlutterBinding：纯 dart test 里 HttpClient 不被测试框架
  // 拦截，本地 HttpServer 冒充 CDN 才能连通（同 online_cache_test 的做法）

  group('OfflineIndex（1.99.16）', () {
    late Directory dir;
    late File file;

    setUp(() {
      dir = _tmpDir();
      file = File(p.join(dir.path, 'offline_index.json'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('put → load 往返；containsHash 按作品前缀命中；tracksOf 反查字幕', () async {
      final index = OfflineIndex(overrideFile: file);
      await index.putWork(OfflineWorkEntry(
        workId: 100,
        title: '作品甲',
        rjCode: 'RJ00000100',
        circleName: '社团',
        coverUrl: 'http://x/cover/100.jpg',
        addedAt: DateTime(2026, 10, 3),
        files: {
          '100/1': const OfflineFileEntry(
              kind: 'audio', size: 1234, title: '音轨1', folder: '子目录'),
          '100/9': const OfflineFileEntry(
              kind: 'lyrics', size: 0, title: '音轨1', linkedHash: '100/1'),
          '100/cover': const OfflineFileEntry(kind: 'cover', size: 0, title: '封面'),
        },
      ));

      final reloaded = OfflineIndex(overrideFile: file);
      await reloaded.load();
      expect(reloaded.containsWork(100), isTrue);
      expect(reloaded.containsHash('100/1'), isTrue);
      expect(reloaded.containsHash('100/9'), isTrue);
      expect(reloaded.containsHash('200/1'), isFalse);
      expect(reloaded.containsHash('bogus'), isFalse);

      final tracks = reloaded.tracksOf(100);
      expect(tracks.length, 1);
      expect(tracks.first.hash, '100/1');
      expect(tracks.first.lyricsHash, '100/9');
      expect(tracks.first.size, 1234);
      expect(reloaded.workOf(100)!.totalBytes, 1234);
    });

    test('损坏文件按空索引；removeWork 落盘', () async {
      file.writeAsStringSync('{{{broken');
      final index = OfflineIndex(overrideFile: file);
      await index.load();
      expect(index.allWorks(), isEmpty);

      await index.putWork(OfflineWorkEntry(
        workId: 1,
        title: 't',
        circleName: '',
        coverUrl: '',
        addedAt: DateTime.now(),
        files: const {},
      ));
      final other = OfflineIndex(overrideFile: file);
      await other.load();
      expect(other.containsWork(1), isTrue);
      await other.removeWork(1);
      final third = OfflineIndex(overrideFile: file);
      await third.load();
      expect(third.containsWork(1), isFalse);
    });
  });

  group('OnlineAudioCache.isProtected（离线豁免 LRU，1.99.16）', () {
    late Directory cacheDir;
    late HttpServer server;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(() async {
        await for (final req in server) {
          req.response.add(List.filled(2048, 1));
          await req.response.close();
        }
      }());
    });
    tearDownAll(() async {
      await server.close(force: true);
    });

    setUp(() {
      cacheDir = _tmpDir();
    });
    tearDown(() => cacheDir.deleteSync(recursive: true));

    test('超限淘汰时跳过 isProtected 命中的文件', () async {
      final cache = OnlineAudioCache(
        directory: cacheDir,
        limitBytes: 3 * 1024,
        isProtected: (hash) => hash.startsWith('1/'),
      );
      await cache.init();

      Uri uri(String f) => Uri.parse('http://127.0.0.1:${server.port}/$f');
      expect(await cache.download('1/a', uri('a'), fallbackExtension: 'mp3'),
          isTrue);
      expect(await cache.download('2/b', uri('b'), fallbackExtension: 'mp3'),
          isTrue);

      // 刚下载的文件在 10 分钟保护窗内不会被淘汰——把 2/b 的 mtime 拨旧
      final b = File(p.join(cacheDir.path, '2_b.mp3'));
      await b.setLastModified(
          DateTime.now().subtract(const Duration(minutes: 11)));
      await cache.enforceLimit();

      expect(cache.isCached('1/a'), isTrue, reason: '离线豁免不被淘汰');
      expect(cache.isCached('2/b'), isFalse, reason: '普通缓存被 LRU 淘汰');
    });
  });

  group('OfflineDownloadService（1.99.16）', () {
    late Directory cacheDir;
    late Directory dataDir;
    late HttpServer server;
    late ProviderContainer container;
    late OnlineAudioCache cache;

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(() async {
        await for (final req in server) {
          req.response.add(List.filled(1024, 7));
          await req.response.close();
        }
      }());
    });
    tearDownAll(() async {
      await server.close(force: true);
    });

    setUp(() {
      cacheDir = _tmpDir();
      dataDir = _tmpDir();
      cache = OnlineAudioCache(directory: cacheDir, limitBytes: 1024 * 1024 * 1024);
      container = ProviderContainer(overrides: [
        onlineAudioCacheProvider.overrideWith((ref) => cache),
        onlineClientProvider.overrideWith((ref) =>
            KikoeruClient(baseUrl: 'http://127.0.0.1:${server.port}')),
        offlineIndexProvider
            .overrideWith((ref) => OfflineIndex(overrideFile: File(
                p.join(dataDir.path, 'offline_index.json')))),
      ]);
      addTearDown(() async {
        await container.read(offlineDownloadProvider.notifier).idle;
        container.dispose();
        cacheDir.deleteSync(recursive: true);
        dataDir.deleteSync(recursive: true);
      });
    });

    test('enqueue → 全部文件下载 → 状态 Done、索引登记、文件落盘', () async {
      await cache.init();
      final service = container.read(offlineDownloadProvider.notifier);
      service.enqueue(OfflineDownloadJob(
        workId: 500,
        title: '整包作品',
        rjCode: 'RJ00000500',
        circleName: '社团',
        coverUrl: 'http://${server.port}/cover',
        tracks: [
          _track(500, 1, lyricsHash: '500/90'),
          _track(500, 2),
        ],
      ));

      // 串行下载：3 个文件（2 音频 + 1 字幕）+ 1 封面
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(container.read(offlineDownloadProvider)[500], isA<DownloadDone>());

      final index = container.read(offlineIndexProvider);
      expect(index.containsWork(500), isTrue);
      expect(index.workOf(500)!.files.length, 4); // 2 audio + 1 lyrics + cover
      expect(index.tracksOf(500).length, 2);
      expect(index.tracksOf(500).first.lyricsHash, '500/90');
      expect(cache.isCached('500/1'), isTrue);
      expect(cache.isCached('500/90'), isTrue);
      expect(cache.isCached('500/cover'), isTrue);
      final works = container.read(offlineIndexListProvider);
      expect(works.any((e) => e.workId == 500), isTrue);
    });

    test('重复 enqueue 同作品被忽略；文件粒度跳过已完成', () async {
      await cache.init();
      final service = container.read(offlineDownloadProvider.notifier);
      final job = OfflineDownloadJob(
        workId: 600,
        title: 't',
        circleName: '',
        coverUrl: 'http://${server.port}/cover',
        tracks: [_track(600, 1)],
      );
      service.enqueue(job);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(container.read(offlineDownloadProvider)[600], isA<DownloadDone>());

      // 再次 enqueue：索引已含 → 忽略（状态保持 Done 不重置）
      service.enqueue(job);
      expect(container.read(offlineDownloadProvider)[600], isA<DownloadDone>());
    });
  });
}
