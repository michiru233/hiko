import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kikoeru/data/scanner.dart';
import 'package:kikoeru/models/album.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('kikoeru-scan-test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 生成 44.1kHz 16bit 单声道正弦波 WAV（带淡入淡出）
  void createWav(String path, double frequency, int seconds) {
    const sampleRate = 44100;
    final samples = sampleRate * seconds;
    final dataSize = samples * 2;
    final buffer = BytesBuilder()
      ..add(Uint8List.fromList([0x52, 0x49, 0x46, 0x46])) // RIFF
      ..add(_le32(36 + dataSize))
      ..add(Uint8List.fromList([0x57, 0x41, 0x56, 0x45])) // WAVE
      ..add(Uint8List.fromList([0x66, 0x6D, 0x74, 0x20])) // "fmt "
      ..add(_le32(16))
      ..add(_le16(1)) // PCM
      ..add(_le16(1)) // mono
      ..add(_le32(sampleRate))
      ..add(_le32(sampleRate * 2))
      ..add(_le16(2))
      ..add(_le16(16))
      ..add(Uint8List.fromList([0x64, 0x61, 0x74, 0x61])) // "data"
      ..add(_le32(dataSize));
    for (var i = 0; i < samples; i++) {
      final fade = min(1.0, min(i / 1200, (samples - i) / 1200));
      final sample =
          (7000 * fade * sin(2 * pi * frequency * i / sampleRate)).round();
      buffer.add(_le16(sample));
    }
    File(path).writeAsBytesSync(buffer.toBytes());
  }

  void createPngCover(String path) {
    final image = img.Image(width: 200, height: 200);
    img.fill(image, color: img.ColorRgb8(48, 95, 114));
    img.fillCircle(image, x: 100, y: 90, radius: 50, color: img.ColorRgb8(241, 199, 91));
    File(path).writeAsBytesSync(img.encodePng(image));
  }

  /// 手工构造带 Shift-JIS ID3v2.3 标签的 MP3：TIT2 帧编码标志 = ISO-8859-1，
  /// 字节实际为 Shift-JIS 日文 → 触发 repairText 还原链路（对应真实 DLsite 文件）
  void createShiftJisMp3(String path, String title) {
    final textBytes = shiftJis.encode(title);
    final frameContent = BytesBuilder()
      ..addByte(0x00) // 编码 0 = ISO-8859-1
      ..add(textBytes);
    final frameSize = frameContent.length;
    final frames = BytesBuilder()
      ..add(Uint8List.fromList('TIT2'.codeUnits))
      ..add(_be32(frameSize))
      ..add([0x00, 0x00]) // frame flags
      ..add(frameContent.toBytes());
    final header = BytesBuilder()
      ..add(Uint8List.fromList([0x49, 0x44, 0x33])) // "ID3"
      ..add([0x03, 0x00, 0x00]) // v2.3, 无标志
      ..add(_syncsafe(frames.length))
      ..add(frames.toBytes());
    // MPEG-1 Layer3 帧头（128kbps / 44.1kHz）+ 静音载荷，保证解析器不报错
    final mpeg = BytesBuilder()
      ..add([0xFF, 0xFB, 0x90, 0x00])
      ..add(List.filled(413, 0));
    File(path).writeAsBytesSync([...header.toBytes(), ...mpeg.toBytes()]);
  }

  test('完整导入链路：分组/RJ 提取/自然排序/封面压缩/乱码修复', () async {
    // 1. RJ 前缀专辑 + 中文文件夹封面 + 日文文件名
    final album1 = Directory('${root.path}/RJ01000112_雨夜耳语');
    album1.createSync();
    createWav('${album1.path}/01 プロローグ.wav', 440, 3);
    createWav('${album1.path}/02 本編.wav', 554.37, 4);
    createPngCover('${album1.path}/cover.png');

    // 2. 深层目录 RJ 提取（对应旧版 0.26.0 修复场景）
    final deep = Directory('${root.path}/deep/RJ01234567_深层音声/inner/测试音声');
    deep.createSync(recursive: true);
    createWav('${deep.path}/01.wav', 330, 2);

    // 3. Shift-JIS 标签 MP3（无封面）
    final sjisDir = Directory('${root.path}/sjis');
    sjisDir.createSync();
    createShiftJisMp3('${sjisDir.path}/01.mp3', '雨夜の耳語');

    // 4. 无音频目录（应被忽略）
    Directory('${root.path}/无音频目录').createSync();

    final files = await collectFiles(root.path);
    final groups = groupFilesByFolder(files);

    final albums = <Album>[];
    for (final entry in groups.entries) {
      final album = await scanAlbum(entry.key, entry.value);
      if (album != null) albums.add(album);
    }

    expect(albums.length, 3);

    // 专辑 1：RJ 前缀剥离 + 封面压缩 + 自然排序 + 时长
    final a1 = albums.singleWhere((a) => a.title.contains('雨夜耳语'));
    expect(a1.title, '雨夜耳语');
    expect(a1.rjCode, 'RJ01000112');
    expect(a1.tracks.length, 2);
    expect(a1.tracks[0].name, '01 プロローグ');
    expect(a1.tracks[1].name, '02 本編');
    expect(a1.totalDuration, closeTo(7, 0.5));
    expect(a1.localCover, startsWith('data:image/jpeg'));
    expect(a1.genre, '未分类');
    expect(a1.shape, 'radio');
    expect(a1.sourcePath, album1.path);

    // 专辑 2：深层目录 RJ 号从全层级路径提取
    final a2 = albums.singleWhere((a) => a.title.contains('测试音声'));
    expect(a2.rjCode, 'RJ01234567');

    // 专辑 3：Shift-JIS 标签经 repairText 还原
    final a3 = albums.singleWhere((a) => a.sourcePath == sjisDir.path);
    expect(a3.tracks.single.name, '雨夜の耳語');
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
