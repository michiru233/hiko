import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_reorganizer.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/scanner.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:image/image.dart' as img;

Uint8List _le32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
Uint8List _le16(int v) => Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _be32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.big);
Uint8List _syncsafe(int v) => Uint8List.fromList([
      (v >> 21) & 0x7F,
      (v >> 14) & 0x7F,
      (v >> 7) & 0x7F,
      v & 0x7F,
    ]);

void main() {
  late Directory tempDir;
  late Directory storeDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hiko-reorganize-test');
    storeDir = Directory.systemTemp.createTempSync('hiko-store-test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    if (storeDir.existsSync()) storeDir.deleteSync(recursive: true);
  });

  void createWav(String path, double frequency, int seconds) {
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
    File(path).writeAsBytesSync(buffer.toBytes());
  }

  void createTaggedMp3(
    String path, {
    required String title,
    String? album,
    String artist = '某社团',
    int? trackNumber,
  }) {
    final frames = BytesBuilder();
    void addFrame(String fid, String text) {
      final payload = BytesBuilder()
        ..addByte(0x00)
        ..add(Uint8List.fromList(gbk.encode(text)));
      frames
        ..add(Uint8List.fromList(fid.codeUnits))
        ..add(_be32(payload.length))
        ..add([0x00, 0x00])
        ..add(payload.toBytes());
    }

    addFrame('TIT2', title);
    if (album != null) addFrame('TALB', album);
    addFrame('TPE1', artist);
    if (trackNumber != null) addFrame('TRCK', '$trackNumber');

    final header = BytesBuilder()
      ..add(Uint8List.fromList([0x49, 0x44, 0x33]))
      ..add([0x03, 0x00, 0x00])
      ..add(_syncsafe(frames.length))
      ..add(frames.toBytes());
    final mpeg = BytesBuilder()
      ..add([0xFF, 0xFB, 0x90, 0x00])
      ..add(List.filled(413, 0));
    File(path).writeAsBytesSync([...header.toBytes(), ...mpeg.toBytes()]);
  }

  test('整理单张专辑：检测文件删除并保留用户状态', () async {
    final albumDir = Directory('${tempDir.path}/RJ123456_测试作品');
    albumDir.createSync();
    final f1 = '${albumDir.path}/01 第一轨.wav';
    final f2 = '${albumDir.path}/02 第二轨.wav';
    createWav(f1, 440, 2);
    createWav(f2, 550, 3);

    final initialAlbums = await scanPath(albumDir.path);
    expect(initialAlbums.length, 1);
    final initial = initialAlbums.first.copyWith(
      favorite: true,
      played: 4.5,
      dlsiteTitle: 'DLsite 官方标题',
      tags: ['治愈', '耳语'],
      genre: 'ASMR',
    );

    // 删除第二轨
    File(f2).deleteSync();

    final container = ProviderContainer(
      overrides: [
        libraryStoreProvider.overrideWithValue(
          LibraryStore(overrideDir: storeDir),
        ),
      ],
    );
    addTearDown(container.dispose);

    final reorganizer = container.read(libraryReorganizerProvider);
    final result = await reorganizer.reorganizeSingleAlbum(initial);

    expect(result.albums.length, 1);
    final updated = result.albums.first;
    expect(updated.tracks.length, 1);
    expect(updated.tracks.first.name, '01 第一轨');
    expect(result.stats.tracksRemoved, 1);
    expect(result.stats.updatedAlbums, 1);

    // 验证用户状态是否完整保留
    expect(updated.favorite, isTrue);
    expect(updated.dlsiteTitle, 'DLsite 官方标题');
    expect(updated.tags, ['治愈', '耳语']);
    expect(updated.genre, 'ASMR');
    expect(updated.played, lessThanOrEqualTo(updated.totalDuration));
  });

  test('整理单张专辑：检测新增歌曲及重命名', () async {
    final albumDir = Directory('${tempDir.path}/RJ222222_新增测试');
    albumDir.createSync();
    final f1 = '${albumDir.path}/01 音轨A.wav';
    createWav(f1, 440, 2);

    final initialAlbums = await scanPath(albumDir.path);
    final initial = initialAlbums.first;

    // 新增一首歌，并重命名音轨A
    final f1New = '${albumDir.path}/01 音轨A改名.wav';
    File(f1).renameSync(f1New);
    final f2 = '${albumDir.path}/02 音轨B新增.wav';
    createWav(f2, 550, 3);

    final container = ProviderContainer(
      overrides: [
        libraryStoreProvider.overrideWithValue(
          LibraryStore(overrideDir: storeDir),
        ),
      ],
    );
    addTearDown(container.dispose);

    final reorganizer = container.read(libraryReorganizerProvider);
    final result = await reorganizer.reorganizeSingleAlbum(initial);

    expect(result.albums.length, 1);
    final updated = result.albums.first;
    expect(updated.tracks.length, 2);
    expect(updated.tracks[0].name, '01 音轨A改名');
    expect(updated.tracks[1].name, '02 音轨B新增');
    expect(result.stats.hasChanges, isTrue);
  });

  test('整理单张专辑：检测 ID3 标签修改并同步', () async {
    final albumDir = Directory('${tempDir.path}/RJ333333_标签测试');
    albumDir.createSync();
    final mp3Path = '${albumDir.path}/track.mp3';
    createTaggedMp3(mp3Path, title: '旧歌名', album: '旧专辑名', artist: '旧社团');

    final initialAlbums = await scanPath(albumDir.path);
    final initial = initialAlbums.first;

    // 修改 MP3 标签
    createTaggedMp3(mp3Path, title: '新歌名', album: '新专辑名', artist: '新社团');

    final container = ProviderContainer(
      overrides: [
        libraryStoreProvider.overrideWithValue(
          LibraryStore(overrideDir: storeDir),
        ),
      ],
    );
    addTearDown(container.dispose);

    final reorganizer = container.read(libraryReorganizerProvider);
    final result = await reorganizer.reorganizeSingleAlbum(initial);

    expect(result.albums.length, 1);
    final updated = result.albums.first;
    expect(updated.artist, '新社团');
    expect(updated.tracks.first.name, '新歌名');
    expect(result.stats.tracksModified, 1);
  });

  test('整理全库：同步全部专辑并正确落盘', () async {
    final store = LibraryStore(overrideDir: storeDir);
    final container = ProviderContainer(
      overrides: [
        libraryStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    final dir1 = Directory('${tempDir.path}/RJ001_专辑一')..createSync();
    final dir2 = Directory('${tempDir.path}/RJ002_专辑二')..createSync();
    createWav('${dir1.path}/01.wav', 440, 2);
    createWav('${dir2.path}/01.wav', 550, 3);

    final a1 = (await scanPath(dir1.path)).first.copyWith(favorite: true);
    final a2 = (await scanPath(dir2.path)).first;

    await container.read(libraryProvider.notifier).replaceAll([a1, a2]);

    // 在专辑一中新增一首，并完全删除专辑二
    createWav('${dir1.path}/02.wav', 660, 4);
    dir2.deleteSync(recursive: true);

    final reorganizer = container.read(libraryReorganizerProvider);
    final result = await reorganizer.reorganizeAll();

    expect(result.stats.scannedAlbums, 2);
    expect(result.stats.removedAlbums, 1);
    expect(result.stats.tracksAdded, 1);
    expect(result.albums.length, 1);

    final remaining = result.albums.first;
    expect(remaining.favorite, isTrue);
    expect(remaining.tracks.length, 2);

    // 验证 store 落盘
    final loaded = await store.load();
    expect(loaded.length, 1);
    expect(loaded.first.tracks.length, 2);
  });
}
