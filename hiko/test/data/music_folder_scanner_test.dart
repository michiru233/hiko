import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/import_service.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/music_folder_scanner.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/platform/platform_service.dart';

/// scanPicked（1.99.11）语义单测：增量/全量传给平台的 known 集合、
/// 桌面快速 diff 跳过、全量强制重解析、选中目录不登记。
void main() {
  late Directory tmp;
  late LibraryStore store;
  late Directory dataDir;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hiko-scanpicked');
    dataDir = Directory('${tmp.path}/data')..createSync(recursive: true);
    store = LibraryStore(overrideDir: dataDir);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// 建一个单专辑源目录（RJ 命名 + 1 秒 wav），返回扫出的专辑
  Future<(String, Album)> _makeAlbum(String name, double freq) async {
    final dir = Directory('${tmp.path}/$name')
      ..createSync(recursive: true);
    await _createWav('${dir.path}/01.wav', freq, 1);
    final albums =
        await ImportService(store).scanPath(dir.path);
    return (dir.path, albums.single);
  }

  ProviderContainer _container(_FakePlatform fake, LibraryNotifier notifier) {
    final container = ProviderContainer(overrides: [
      platformServiceProvider.overrideWithValue(fake),
      libraryStoreProvider.overrideWithValue(store),
      libraryProvider.overrideWith((ref) => notifier),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('增量（Android 语义）：known = 全库曲目 URL（非空），新专辑入库', () async {
    final (_, inLib) = await _makeAlbum('RJ11111_已入库', 440);
    final (_, picked) = await _makeAlbum('RJ22222_新专辑', 554);
    final notifier = LibraryNotifier(store);
    await notifier.mergeNew([inLib]);
    final fake = _FakePlatform(safMode: true, safAlbums: [picked]);
    final container = _container(fake, notifier);

    final added = await container
        .read(musicFolderScannerProvider)
        .scanPicked(full: false);

    expect(added, 1);
    expect(fake.capturedKnown, isNotEmpty);
    expect(fake.capturedKnown, containsAll(inLib.tracks.map((t) => t.url)));
    expect(container.read(libraryProvider).length, 2);
  });

  test('全量（Android 语义）：known 传空集合 = 全量重建', () async {
    final (_, inLib) = await _makeAlbum('RJ11111_已入库', 440);
    final notifier = LibraryNotifier(store);
    await notifier.mergeNew([inLib]);
    final fake = _FakePlatform(safMode: true);
    final container = _container(fake, notifier);

    await container
        .read(musicFolderScannerProvider)
        .scanPicked(full: true);

    expect(fake.capturedKnown, isEmpty);
  });

  test('Android 用户取消（albums 空）不产生新增', () async {
    final notifier = LibraryNotifier(store);
    final fake = _FakePlatform(safMode: true);
    final container = _container(fake, notifier);

    final added = await container
        .read(musicFolderScannerProvider)
        .scanPicked(full: false);

    expect(added, 0);
    expect(container.read(libraryProvider), isEmpty);
  });

  test('桌面增量：新目录正常扫描入库', () async {
    final (path, _) = await _makeAlbum('RJ33333_桌面新专辑', 440);
    final notifier = LibraryNotifier(store);
    final fake = _FakePlatform(safMode: false, pickResult: [path]);
    final container = _container(fake, notifier);

    var progressCalls = 0;
    final added = await container
        .read(musicFolderScannerProvider)
        .scanPicked(full: false, onProgress: (_) => progressCalls++);

    expect(added, 1);
    expect(fake.pickCalls, 1);
    expect(progressCalls, greaterThan(0));
    expect(container.read(libraryProvider).length, 1);
  });

  test('桌面增量：目录内文件全部已知 → 快速 diff 跳过，不解析不新增', () async {
    final (path, album) = await _makeAlbum('RJ11111_已入库', 440);
    final notifier = LibraryNotifier(store);
    await notifier.mergeNew([album]);
    final fake = _FakePlatform(safMode: false, pickResult: [path]);
    final container = _container(fake, notifier);

    var progressCalls = 0;
    final added = await container
        .read(musicFolderScannerProvider)
        .scanPicked(full: false, onProgress: (_) => progressCalls++);

    expect(added, 0);
    expect(progressCalls, 0); // 没走 scanPath，秒回
    expect(container.read(libraryProvider).length, 1);
  });

  test('桌面全量：文件全部已知仍强制重解析（修复存量元数据/封面）', () async {
    final (path, album) = await _makeAlbum('RJ11111_已入库', 440);
    final notifier = LibraryNotifier(store);
    await notifier.mergeNew([album]);
    final fake = _FakePlatform(safMode: false, pickResult: [path]);
    final container = _container(fake, notifier);

    var progressCalls = 0;
    final added = await container
        .read(musicFolderScannerProvider)
        .scanPicked(full: true, onProgress: (_) => progressCalls++);

    expect(progressCalls, greaterThan(0)); // 全量：跳过快速 diff，真实重扫
    expect(added, 0); // 内容没变，merge 后数量不变
    expect(container.read(libraryProvider).length, 1);
  });
}

/// 桩平台服务：safMode=true 模拟 Android（选择器内嵌原生 importAudioFolder）；
/// false 模拟桌面（importAudioFolder 返回 null → pickDirectories）。
class _FakePlatform extends DesktopPlatformService {
  _FakePlatform({
    required bool safMode,
    List<Album> safAlbums = const [],
    this.pickResult,
  })  : _safMode = safMode,
        _safAlbums = safAlbums;

  final bool _safMode;
  final List<Album> _safAlbums;
  final List<String>? pickResult;
  Set<String> capturedKnown = const {};
  int pickCalls = 0;

  @override
  Future<ImportScanResult?> importAudioFolder({
    void Function(int, int, String, String)? onProgress,
    Set<String> known = const {},
  }) async {
    capturedKnown = known;
    if (!_safMode) return null;
    return (albums: _safAlbums, treeUri: 'content://picked');
  }

  @override
  Future<List<String>?> pickDirectories() async {
    pickCalls++;
    return pickResult;
  }
}

Future<void> _createWav(String path, double frequency, int seconds) async {
  const sampleRate = 44100;
  final samples = sampleRate * seconds;
  final dataSize = samples * 2;
  final buffer = BytesBuilder()
    ..add(Uint8List.fromList([0x52, 0x49, 0x46, 0x46]))
    ..add(_le32(36 + dataSize))
    ..add(Uint8List.fromList([0x57, 0x41, 0x56, 0x45]))
    ..add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20]))
    ..add(_le32(16))
    ..add(_le16(1))
    ..add(_le16(1))
    ..add(_le32(sampleRate))
    ..add(_le32(sampleRate * 2))
    ..add(_le16(2))
    ..add(_le16(16))
    ..add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61]))
    ..add(_le32(dataSize));
  for (var i = 0; i < samples; i++) {
    final fade = min(1.0, min(i / 1200, (samples - i) / 1200));
    final sample =
        (7000 * fade * sin(2 * pi * frequency * i / sampleRate)).round();
    buffer.add(_le16(sample));
  }
  await File(path).writeAsBytes(buffer.toBytes());
}

Uint8List _le16(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
Uint8List _le32(int v) => Uint8List.fromList([
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ]);
