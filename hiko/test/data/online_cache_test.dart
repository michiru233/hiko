import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/online_audio_cache.dart';
import 'package:path/path.dart' as p;

/// 在线音频缓存单测：用本地 HttpServer 冒充 CDN，不访问外网。
void main() {
  late Directory tmp;
  late OnlineAudioCache cache;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hiko-online-cache-test');
    cache = OnlineAudioCache(directory: tmp, limitBytes: 4 * 1024 * 1024);
    await cache.init();
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// 起一个返回指定字节的服务端；[declaredLength] 与 [body] 长度不一致时用于测截断
  Future<HttpServer> startServer(
    List<int> body, {
    String contentType = 'audio/mpeg',
    int? declaredLength,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.headers.contentType = ContentType.parse(contentType);
      final length = declaredLength ?? body.length;
      request.response.headers.contentLength = length;
      request.response.add(body);
      request.response.close().catchError((_) {});
    });
    addTearDown(() => server.close(force: true));
    return server;
  }

  test('下载成功后入库，文件名带服务端 Content-Type 推出的扩展名', () async {
    final body = List<int>.generate(2048, (i) => i % 256);
    final server = await startServer(body);

    final ok = await cache.download(
      '1657200/1937305',
      Uri.parse('http://127.0.0.1:${server.port}/api/media/stream/x'),
    );

    expect(ok, isTrue);
    expect(cache.isCached('1657200/1937305'), isTrue);
    final path = cache.cachedPath('1657200/1937305');
    expect(path, isNotNull);
    expect(p.basename(path!), '1657200_1937305.mp3');
    expect(await File(path).readAsBytes(), body);
  });

  test('Content-Type 推不出扩展名时回退调用方给的扩展名', () async {
    final body = List<int>.filled(512, 1);
    final server = await startServer(body, contentType: 'application/octet-stream');

    final ok = await cache.download(
      '1/2',
      Uri.parse('http://127.0.0.1:${server.port}/f'),
      fallbackExtension: 'm4b',
    );

    expect(ok, isTrue);
    expect(p.basename(cache.cachedPath('1/2')!), '1_2.m4b');
  });

  test('实际长度与声明不符（截断）时不入库，并清掉 .part 残留', () async {
    final body = List<int>.filled(500, 2);
    final server = await startServer(body, declaredLength: 1000);

    final ok = await cache.download(
      '3/4',
      Uri.parse('http://127.0.0.1:${server.port}/f'),
      expectedSize: 1000,
    );

    expect(ok, isFalse);
    expect(cache.isCached('3/4'), isFalse);
    expect(
      tmp.listSync().where((e) => e.path.endsWith('.part')),
      isEmpty,
    );
  });

  test('同一 hash 并发下载复用同一任务，不重复请求', () async {
    var hits = 0;
    final body = List<int>.filled(1024, 3);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      hits++;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.headers.contentLength = body.length;
      request.response.add(body);
      request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final uri = Uri.parse('http://127.0.0.1:${server.port}/f');
    final results = await Future.wait([
      cache.download('5/6', uri),
      cache.download('5/6', uri),
      cache.download('5/6', uri),
    ]);

    expect(results, [true, true, true]);
    expect(hits, 1);
  });

  test('已缓存时直接返回 true，不再发请求', () async {
    var hits = 0;
    final body = List<int>.filled(256, 4);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      hits++;
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.headers.contentLength = body.length;
      request.response.add(body);
      request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final uri = Uri.parse('http://127.0.0.1:${server.port}/f');
    await cache.download('7/8', uri);
    final again = await cache.download('7/8', uri);

    expect(again, isTrue);
    expect(hits, 1);
  });

  test('重建实例后从磁盘索引恢复命中（模拟重启）', () async {
    final body = List<int>.filled(300, 5);
    final server = await startServer(body);
    await cache.download(
      '9/10',
      Uri.parse('http://127.0.0.1:${server.port}/f'),
    );

    final reopened = OnlineAudioCache(directory: tmp);
    await reopened.init();
    expect(reopened.isCached('9/10'), isTrue);
    expect(reopened.cachedPath('9/10'), isNotNull);
  });

  test('totalBytes 统计占用，clear 清空', () async {
    final body = List<int>.filled(4096, 6);
    final server = await startServer(body);
    final uri = Uri.parse('http://127.0.0.1:${server.port}/f');
    await cache.download('11/12', uri);
    await cache.download('13/14', uri);

    expect(await cache.totalBytes(), 8192);

    await cache.clear();
    expect(await cache.totalBytes(), 0);
    expect(cache.isCached('11/12'), isFalse);
  });

  test('超限时按 mtime 淘汰最旧，被 pin（正在播放）的文件不动', () async {
    const chunk = 400 * 1024;
    final oldest = File(p.join(tmp.path, '1_1.mp3'));
    final middle = File(p.join(tmp.path, '1_2.mp3'));
    final newest = File(p.join(tmp.path, '1_3.mp3'));
    for (final f in [oldest, middle, newest]) {
      await f.writeAsBytes(List<int>.filled(chunk, 7));
    }
    final base = DateTime.now().subtract(const Duration(hours: 2));
    await oldest.setLastModified(base);
    await middle.setLastModified(base.add(const Duration(minutes: 1)));
    await newest.setLastModified(base.add(const Duration(minutes: 2)));

    // 上限 900KB：三个 400KB 文件必须淘汰到 900KB 以下（删一个即可）
    final limited = OnlineAudioCache(directory: tmp, limitBytes: 900 * 1024);
    await limited.init();
    limited.pin('1/1'); // 最旧的正在播放
    await limited.enforceLimit();

    expect(await oldest.exists(), isTrue, reason: '正在播放的文件不得被淘汰');
    expect(await newest.exists(), isTrue, reason: '最新的文件保留');
    expect(await middle.exists(), isFalse, reason: '未 pin 的最旧文件应被淘汰');
    expect(limited.isCached('1/2'), isFalse, reason: '索引需同步移除');
  });

  test('超过 1 小时的中断残留 .part 被清理', () async {
    final stale = File(p.join(tmp.path, '20_21.part'));
    await stale.writeAsBytes(List<int>.filled(64, 8));
    await stale.setLastModified(
      DateTime.now().subtract(const Duration(hours: 3)),
    );

    await cache.enforceLimit();

    expect(await stale.exists(), isFalse);
  });

  test('hash ↔ 文件名映射可往返（含多级路径分隔符）', () async {
    final body = List<int>.filled(128, 9);
    final server = await startServer(body);
    final uri = Uri.parse('http://127.0.0.1:${server.port}/f');
    await cache.download('1234567/7654321', uri);

    final reopened = OnlineAudioCache(directory: tmp);
    await reopened.init();
    expect(reopened.isCached('1234567/7654321'), isTrue);
  });
}
