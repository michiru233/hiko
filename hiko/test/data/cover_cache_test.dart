import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/covers/cover_cache.dart';
import 'package:path/path.dart' as p;

void main() {
  group('LruCache LRU 淘汰语义（1.48：禁止整表 clear）', () {
    test('超容淘汰最旧条目', () {
      final c = LruCache<String, int>(2);
      c.put('a', 1);
      c.put('b', 2);
      c.put('c', 3); // a 被淘汰
      expect(c.peek('a'), isNull);
      expect(c.peek('b'), 2);
      expect(c.peek('c'), 3);
      expect(c.length, 2);
    });

    test('get 命中会重排为最近使用，改变淘汰对象', () {
      final c = LruCache<String, int>(2);
      c.put('a', 1);
      c.put('b', 2);
      expect(c.get('a'), 1); // a 变为最近使用，b 成为最旧
      c.put('c', 3); // 淘汰 b，而非 a
      expect(c.peek('a'), 1);
      expect(c.peek('b'), isNull);
      expect(c.peek('c'), 3);
    });

    test('重复 put 同键更新且计一次', () {
      final c = LruCache<String, int>(2);
      c.put('a', 1);
      c.put('a', 9);
      c.put('b', 2);
      expect(c.length, 2);
      expect(c.peek('a'), 9);
    });
  });

  group('decodeDataUrl 纯解码', () {
    test('合法 data: URL 解码还原', () {
      final url = 'data:image/png;base64,AAECAw==';
      final bytes = decodeDataUrl(url);
      expect(bytes, isNotNull);
      expect(bytes, Uint8List.fromList([0, 1, 2, 3]));
    });

    test('非法输入返回 null 不抛异常', () {
      expect(decodeDataUrl('data:image/png;base64,!!!'), isNull);
      expect(decodeDataUrl(''), isNull);
    });
  });

  group('CoverCache 内存 LRU', () {
    test('load 命中内存不再解码；超容逐条淘汰不清空', () async {
      final cache = CoverCache(memoryCapacity: 2);
      final a = await cache.load('data:image/png;base64,AA==');
      final b = await cache.load('data:image/png;base64,AQ==');
      // 再 load a：内存命中（SynchronousFuture 立即有值）
      expect(cache.peek('data:image/png;base64,AA=='), a);
      expect(cache.peek('data:image/png;base64,AQ=='), b);
      final c = await cache.load('data:image/png;base64,Ag==');
      expect(c, isNotNull);
      expect(cache.peek('data:image/png;base64,AA=='), isNull); // LRU 淘汰 a
      expect(cache.peek('data:image/png;base64,AQ=='), b); // 其余仍在
    });

    test('同一 dataUrl 并发 load 复用同一 Future', () async {
      final cache = CoverCache();
      final url = 'data:image/png;base64,AAECAw==';
      final f1 = cache.load(url);
      final f2 = cache.load(url);
      expect(identical(f1, f2), isTrue);
      expect(await f1, Uint8List.fromList([0, 1, 2, 3]));
      // 完成后 in-flight 表清空，不长期持有结果
      expect(cache.peek(url), isNotNull);
    });

    test('非法 data: URL 返回 null', () async {
      final cache = CoverCache();
      expect(await cache.load('data:image/png;base64,!!!'), isNull);
    });
  });

  group('CoverDiskCache 磁盘 LRU（tmp 目录注入）', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('hiko_cover_cache_test');
    });

    tearDown(() async {
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('put 后 get 还原字节；未命中返回 null', () async {
      final cache = CoverDiskCache(directory: tmp);
      await cache.init();
      await cache.put('url-a', Uint8List.fromList([1, 2, 3]));
      expect(await cache.get('url-a'), Uint8List.fromList([1, 2, 3]));
      expect(await cache.get('url-never'), isNull);
    });

    test('同 dataUrl 稳定映射同一文件', () async {
      final cache = CoverDiskCache(directory: tmp);
      await cache.init();
      expect(cache.keyFor('url-x'), cache.keyFor('url-x'));
      expect(cache.keyFor('url-x'), isNot(cache.keyFor('url-y')));
    });

    test('超容按 mtime LRU 淘汰：被触碰的保留', () async {
      final cache = CoverDiskCache(directory: tmp, capacity: 2);
      await cache.init();
      await cache.put('url-1', Uint8List.fromList([1]));
      await Future.delayed(const Duration(milliseconds: 20));
      await cache.put('url-2', Uint8List.fromList([2]));
      await Future.delayed(const Duration(milliseconds: 20));
      expect(await cache.get('url-1'), isNotNull); // 触碰 mtime → 最新
      await Future.delayed(const Duration(milliseconds: 20));
      await cache.put('url-3', Uint8List.fromList([3])); // 淘汰最旧的 url-2
      final files = tmp.listSync().whereType<File>().length;
      expect(files, 2);
      expect(await cache.get('url-1'), isNotNull);
      expect(await cache.get('url-2'), isNull);
      expect(await cache.get('url-3'), isNotNull);
    });

    test('未 init 时不落盘', () async {
      final cache = CoverDiskCache(directory: Directory(p.join(tmp.path, 'x')));
      await cache.put('url-a', Uint8List.fromList([1]));
      expect(cache.directory.existsSync(), isFalse);
      expect(await cache.get('url-a'), isNull);
    });
  });
}
