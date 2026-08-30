import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// LRU 内存缓存：LinkedHashMap 保持插入序，get 命中即重插（标记最近使用），
/// 超容淘汰最旧一条。1.48 前旧实现超 300 张直接整表 clear()，会把整页可见
/// 封面一起丢光导致滚动反复重解码——本类禁止这种行为。
class LruCache<K, V> {
  LruCache(this.capacity) : assert(capacity > 0);

  final int capacity;
  final _map = <K, V>{};

  int get length => _map.length;

  V? peek(K key) => _map[key]; // 只读，不更新新旧序

  V? get(K key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v;
    return v;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }
}

/// data: URL → 字节的纯解码函数（可跑在 Isolate 内）；非法输入返回 null
Uint8List? decodeDataUrl(String dataUrl) {
  try {
    final commaIndex = dataUrl.indexOf(',');
    final b64 = commaIndex >= 0 ? dataUrl.substring(commaIndex + 1) : dataUrl;
    if (b64.isEmpty) return null;
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

/// 封面三级缓存：内存 LRU(300) → 磁盘 LRU(2000) → Isolate.run 解码并落盘。
/// Base64 解码不再占用 UI 主线程；磁盘命中让重启后同一封面免二次解码。
class CoverCache {
  CoverCache({int memoryCapacity = 300, CoverDiskCache? diskCache})
      : _memory = LruCache(memoryCapacity),
        _disk = diskCache;

  static final CoverCache instance = CoverCache();

  final LruCache<String, Uint8List> _memory;
  CoverDiskCache? _disk;
  final _inflight = <String, Future<Uint8List?>>{};

  /// 初始化磁盘缓存（Application Support/hiko/covers）；失败静默降级为纯内存
  Future<void> init() async {
    if (_disk != null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _disk = CoverDiskCache(
        directory: Directory(p.join(dir.path, 'covers')),
      );
      await _disk!.init();
    } catch (_) {
      _disk = null;
    }
  }

  /// 构建期同步快路径：内存命中返回字节，未命中返回 null（调用方走异步兜底）
  Uint8List? peek(String dataUrl) => _memory.get(dataUrl);

  /// 异步取字节：内存未命中 → 磁盘 → Isolate 解码 + 异步落盘
  Future<Uint8List?> load(String dataUrl) {
    final cached = _memory.get(dataUrl);
    if (cached != null) return SynchronousFuture(cached);
    final existing = _inflight[dataUrl];
    if (existing != null) return existing;
    final task = _loadSlow(dataUrl);
    // 完成后移除：completed Future 若滞留会绕过 LRU 长期持有全部结果
    task.whenComplete(() => _inflight.remove(dataUrl));
    _inflight[dataUrl] = task;
    return task;
  }

  Future<Uint8List?> _loadSlow(String dataUrl) async {
    try {
      final diskBytes = await _disk?.get(dataUrl);
      if (diskBytes != null) {
        _memory.put(dataUrl, diskBytes);
        return diskBytes;
      }
    } catch (_) {
      // 磁盘读失败降级为解码
    }
    final Uint8List? decoded;
    try {
      decoded = await Isolate.run(() => decodeDataUrl(dataUrl));
    } catch (_) {
      return null;
    }
    if (decoded == null) return null;
    _memory.put(dataUrl, decoded);
    try {
      await _disk?.put(dataUrl, decoded);
    } catch (_) {
      // 落盘失败容忍
    }
    return decoded;
  }
}

/// 磁盘封面缓存：文件名 = sha1(dataUrl)，以文件 mtime 作 LRU 依据
/// （读即触碰、写即置新，超容删最旧）。纯 dart:io，目录可注入（单测用 tmp 目录）。
class CoverDiskCache {
  CoverDiskCache({required this.directory, this.capacity = 2000});

  final Directory directory;
  final int capacity;
  bool _inited = false;

  Future<void> init() async {
    await directory.create(recursive: true);
    _inited = true;
  }

  String keyFor(String dataUrl) =>
      sha1.convert(utf8.encode(dataUrl)).toString();

  Future<Uint8List?> get(String dataUrl) async {
    if (!_inited) return null;
    final f = File(p.join(directory.path, keyFor(dataUrl)));
    if (!f.existsSync()) return null;
    final bytes = await f.readAsBytes();
    try {
      await f.setLastModified(DateTime.now()); // 触碰 mtime 标记最近使用
    } catch (_) {
      // mtime 更新失败只影响淘汰顺序，容忍
    }
    return bytes;
  }

  Future<void> put(String dataUrl, Uint8List bytes) async {
    if (!_inited) return;
    await directory.create(recursive: true);
    final f = File(p.join(directory.path, keyFor(dataUrl)));
    await f.writeAsBytes(bytes, flush: true);
    await _evict();
  }

  Future<void> _evict() async {
    final files = directory.listSync().whereType<File>().toList()
      ..sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));
    for (var i = 0; i < files.length - capacity; i++) {
      try {
        await files[i].delete();
      } catch (_) {
        // 已被并发删除等，容忍
      }
    }
  }
}
