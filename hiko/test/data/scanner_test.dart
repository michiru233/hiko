import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/scanner.dart';
import 'package:hiko/models/album.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hiko-scan-test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
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
      final sample = (7000 * fade * sin(2 * pi * frequency * i / sampleRate)).round();
      buffer.add(_le16(sample));
    }
    File(path).writeAsBytesSync(buffer.toBytes());
  }

  void createPngCover(String path) {
    final image = img.Image(width: 200, height: 200);
    img.fill(image, color: img.ColorRgb8(48, 95, 114));
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  /// 构造带完整 ID3v2.3 标签的 MP3（TIT2/TALB/TPE1/TRCK/APIC）
  void createTaggedMp3(
    String path, {
    required String title,
    required String album,
    String artist = '某社团',
    String? albumArtist,
    int? trackNumber,
    String? charsetName, // gbk / shiftJis / 空 = latin1
  }) {
    Uint8List enc(String s) {
      if (charsetName == 'gbk' || charsetName == null) {
        return Uint8List.fromList(gbk.encode(s));
      }
      return Uint8List.fromList(shiftJis.encode(s));
    }

    final frames = BytesBuilder();
    void addFrame(String fid, String text) {
      final payload = BytesBuilder()..addByte(0x00)..add(enc(text));
      frames
        ..add(Uint8List.fromList(fid.codeUnits))
        ..add(_be32(payload.length))
        ..add([0x00, 0x00])
        ..add(payload.toBytes());
    }

    addFrame('TIT2', title);
    addFrame('TALB', album);
    addFrame('TPE1', artist);
    if (albumArtist != null) addFrame('TPE2', albumArtist);
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

  test('混合分组：跨文件夹同 ALBUM 标签聚合 + TRACKNUMBER 排序', () async {
    // 两个文件夹各一首，ALBUM 标签相同 → 聚合成一张专辑
    final dirA = Directory('${root.path}/folderA/RJ11111_作品甲');
    dirA.createSync(recursive: true);
    final dirB = Directory('${root.path}/folderB/RJ11111_作品甲');
    dirB.createSync(recursive: true);
    // trackNumber 乱序：B 是第 1 首，A 是第 2 首
    createTaggedMp3('${dirB.path}/02 第二首.mp3',
        title: '第二首', album: '作品甲', artist: '社团X', trackNumber: 2);
    createTaggedMp3('${dirA.path}/01 第一首.mp3',
        title: '第一首', album: '作品甲', artist: '社团X', trackNumber: 1);

    final albums = await scanPath(root.path);

    expect(albums.length, 1, reason: '同 ALBUM 标签跨文件夹聚合');
    final album = albums.single;
    expect(album.title, '作品甲');
    expect(album.artist, '社团X');
    expect(album.tracks.length, 2);
    // TRACKNUMBER 排序：第一首在前
    expect(album.tracks[0].name, '第一首');
    expect(album.tracks[1].name, '第二首');
  });

  test('无 ALBUM 标签回退文件夹分组（DLsite 结构）+ 深层 RJ + 封面', () async {
    // RJ 前缀目录 + 中文文件名 + PNG 封面
    final album1 = Directory('${root.path}/RJ01000112_雨夜耳语');
    album1.createSync();
    createWav('${album1.path}/01 プロローグ.wav', 440, 3);
    createWav('${album1.path}/02 本編.wav', 554.37, 4);
    createPngCover('${album1.path}/cover.png');

    // 深层目录 RJ 提取
    final deep = Directory('${root.path}/deep/RJ01234567_深层音声/inner/测试音声');
    deep.createSync(recursive: true);
    createWav('${deep.path}/01.wav', 330, 2);

    // 无音频目录忽略
    Directory('${root.path}/无音频目录').createSync();

    final albums = await scanPath(root.path);

    expect(albums.length, 2);

    final a1 = albums.singleWhere((a) => a.title.contains('雨夜耳语'));
    expect(a1.title, '雨夜耳语');
    expect(a1.rjCode, 'RJ01000112');
    expect(a1.tracks.length, 2);
    expect(a1.tracks[0].name, '01 プロローグ');
    expect(a1.totalDuration, closeTo(7, 0.5));
    expect(a1.localCover, startsWith('data:image/jpeg'));

    final a2 = albums.singleWhere((a) => a.title.contains('测试音声'));
    expect(a2.rjCode, 'RJ01234567');
  });

  test('Shift-JIS 标签修复 + 专辑艺术家优先', () async {
    final dir = Directory('${root.path}/sjis');
    dir.createSync();
    createTaggedMp3('${dir.path}/01.mp3',
        title: '雨夜の耳語',
        album: '雨夜の耳語',
        albumArtist: 'サークルY',
        charsetName: 'shiftJis');

    final albums = await scanPath(root.path);
    expect(albums.single.tracks.single.name, '雨夜の耳語');
    expect(albums.single.artist, 'サークルY'); // 专辑艺术家优先
  });

  test('GBK 中文标签修复', () async {
    final dir = Directory('${root.path}/gbk');
    dir.createSync();
    createTaggedMp3('${dir.path}/01.mp3',
        title: '第一章 中文标签', album: '中文测试专辑', charsetName: 'gbk');

    final albums = await scanPath(root.path);
    expect(albums.single.title, '中文测试专辑');
    expect(albums.single.tracks.single.name, '第一章 中文标签');
  });
}

Uint8List _le16(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
Uint8List _le32(int v) => Uint8List.fromList([
      v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF,
    ]);
Uint8List _be32(int v) => Uint8List.fromList([
      (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF,
    ]);
Uint8List _syncsafe(int v) => Uint8List.fromList([
      (v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F,
    ]);
