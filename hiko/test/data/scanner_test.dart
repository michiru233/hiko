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
    String? album,
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
    if (album != null) addFrame('TALB', album);
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

  /// 构造带内嵌封面（APIC）的 MP3：在 createTaggedMp3 基础上追加 APIC 帧。
  /// APIC 帧体 = [encoding=0x03][mime\0][pictureType=0x03][desc\0][png bytes]。
  void createTaggedMp3WithCover(
    String path, {
    required String title,
    String? album,
    String artist = '某社团',
    String? albumArtist,
    int? trackNumber,
  }) {
    // 先复用普通标签构造，但要在贴头上多写一个 APIC 帧，这里单独重写帧序列
    Uint8List encText(String s) => Uint8List.fromList(gbk.encode(s));

    final frames = BytesBuilder();
    void addFrame(String fid, String text) {
      final payload = BytesBuilder()..addByte(0x00)..add(encText(text));
      frames
        ..add(Uint8List.fromList(fid.codeUnits))
        ..add(_be32(payload.length))
        ..add([0x00, 0x00])
        ..add(payload.toBytes());
    }

    final pngBytes = img.encodePng(img.fill(
        img.Image(width: 200, height: 200), color: img.ColorRgb8(120, 80, 60)));

    addFrame('TIT2', title);
    if (album != null) addFrame('TALB', album);
    addFrame('TPE1', artist);
    if (albumArtist != null) addFrame('TPE2', albumArtist);
    if (trackNumber != null) addFrame('TRCK', '$trackNumber');

    // APIC 帧
    final apicPayload = BytesBuilder()
      ..addByte(0x03) // encoding: UTF-8
      ..add(Uint8List.fromList('image/png'.codeUnits))
      ..addByte(0x00)
      ..addByte(0x03) // picture type: 3 (front cover)
      ..addByte(0x00) // 描述为空
      ..add(pngBytes);
    frames
      ..add(Uint8List.fromList('APIC'.codeUnits))
      ..add(_be32(apicPayload.length))
      ..add([0x00, 0x00])
      ..add(apicPayload.toBytes());

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

  test('无 ALBUM 标签曲目继承目录多数专辑名 → 不拆散聚合', () async {
    final dir = Directory('${root.path}/RJ99999_作品甲');
    dir.createSync();
    // 仅第一首带 ALBUM 标签，第二首无标签 → 继承目录专辑名进标签组
    createTaggedMp3('${dir.path}/01 第一首.mp3',
        title: '第一首', album: '作品甲', artist: '社团X', trackNumber: 1);
    createTaggedMp3('${dir.path}/02 第二首.mp3',
        title: '第二首', artist: '社团X', trackNumber: 2);

    final albums = await scanPath(root.path);

    expect(albums.length, 1, reason: '无标签曲目吸收进同目录标签组');
    expect(albums.single.title, '作品甲');
    expect(albums.single.tracks.length, 2);
    expect(albums.single.tracks[0].name, '第一首');
    expect(albums.single.tracks[1].name, '第二首');
  });

  test('跨目录标签组封面回退（封面只在其中一个目录）', () async {
    final dirA = Directory('${root.path}/folderA/RJ11111_作品甲');
    dirA.createSync(recursive: true);
    final dirB = Directory('${root.path}/folderB/RJ11111_作品甲');
    dirB.createSync(recursive: true);
    createTaggedMp3('${dirA.path}/01 第一首.mp3',
        title: '第一首', album: '作品甲', artist: '社团X', trackNumber: 1);
    createTaggedMp3('${dirB.path}/02 第二首.mp3',
        title: '第二首', album: '作品甲', artist: '社团X', trackNumber: 2);
    createPngCover('${dirB.path}/cover.png');

    final albums = await scanPath(root.path);

    expect(albums.length, 1);
    expect(albums.single.localCover, startsWith('data:image/jpeg'),
        reason: '标签组跨目录封面回退');
  });

  test('专辑元数据取首个含 ALBUM 标签音轨 + metaFromFolder 标志（1.32）', () async {
    // 有标签：第 1 首（TRCK=1）的 TPE2 决定艺术家；title 来自 ALBUM 标签
    final dirTagged = Directory('${root.path}/tagged');
    dirTagged.createSync();
    createTaggedMp3('${dirTagged.path}/01.mp3',
        title: '第一首', album: '标签专辑名', artist: '艺人A', albumArtist: '社团甲', trackNumber: 1);
    createTaggedMp3('${dirTagged.path}/02.mp3',
        title: '第二首', album: '标签专辑名', artist: '艺人B', albumArtist: '社团甲', trackNumber: 2);
    // 无标签：标题回退文件夹名，metaFromFolder=true（供 DLsite 兜底）
    final dirPlain = Directory('${root.path}/RJ0399999');
    dirPlain.createSync();
    createWav('${dirPlain.path}/01.wav', 440, 2);

    final albums = await scanPath(root.path);

    final tagged = albums.singleWhere((a) => a.tracks.length == 2);
    expect(tagged.title, '标签专辑名');
    expect(tagged.artist, '社团甲', reason: '首个含标签音轨的专辑艺术家优先');
    expect(tagged.metaFromFolder, isFalse, reason: '标题来自标签，不需要兜底');

    final plain = albums.singleWhere((a) => a.tracks.length == 1);
    expect(plain.title, 'RJ0399999', reason: '无标签回退文件夹名');
    expect(plain.rjCode, 'RJ0399999');
    expect(plain.metaFromFolder, isTrue, reason: '标题来自文件夹回退，标记待 DLsite 兜底');
  });

  test('封面查找扩到父目录（1.32：图在 RJ 目录、音频在其子目录）', () async {
    // DLsite 常见结构：RJ 目录放封面，音频在「音声」子目录 → 旧版只查组内目录丢封面
    final rj = Directory('${root.path}/RJ0555555_父目录封面作品');
    final inner = Directory('${rj.path}/音声');
    inner.createSync(recursive: true);
    createWav('${inner.path}/01.wav', 440, 2);
    createPngCover('${rj.path}/cover.png');

    final albums = await scanPath(root.path);

    expect(albums.single.localCover, startsWith('data:image/jpeg'),
        reason: '封面在专辑目录的父目录也要能找到');
  });

  test('导入进度分阶段实时回调（files → albums）', () async {
    // 3 个文件分布在 2 个目录 → files 阶段 total=3，albums 阶段 total=2
    final dirA = Directory('${root.path}/folderA/RJ11111_作品甲');
    dirA.createSync(recursive: true);
    final dirB = Directory('${root.path}/folderB/RJ22222_作品乙');
    dirB.createSync(recursive: true);
    createTaggedMp3('${dirA.path}/01 第一首.mp3',
        title: '第一首', album: '作品甲', artist: '社团X', trackNumber: 1);
    createTaggedMp3('${dirA.path}/02 第二首.mp3',
        title: '第二首', album: '作品甲', artist: '社团X', trackNumber: 2);
    createTaggedMp3('${dirB.path}/01 第一首.mp3',
        title: '第一首', album: '作品乙', artist: '社团Y', trackNumber: 1);

    final events = <(int, int, String)>[];
    await scanPath(root.path, onProgress: (p, t, phase) {
      events.add((p, t, phase));
    });

    final filesEvents = events.where((e) => e.$3 == 'files').toList();
    final albumsEvents = events.where((e) => e.$3 == 'albums').toList();
    expect(filesEvents, isNotEmpty);
    expect(filesEvents.last.$2, 3, reason: 'files 阶段 total = 音频文件数');
    expect(filesEvents.last.$1, 3);
    expect(albumsEvents, isNotEmpty);
    expect(albumsEvents.last.$2, 2, reason: 'albums 阶段 total = 专辑数');
    expect(albumsEvents.last.$1, 2);
    // 阶段顺序：全部 files 事件先于 albums 事件
    final firstAlbumEvent = events.indexWhere((e) => e.$3 == 'albums');
    expect(events.take(firstAlbumEvent).every((e) => e.$3 == 'files'), isTrue);
  });

  test('封面取第一首内嵌 APIC（优先于外置功能图）→ 元数据第一首优先', () async {
    // DLsite 常见坑：音频内嵌了真实封面 APIC，外层目录却放着一张「曲目列表/角色图」。
    // 本次修复：内嵌封面优先，避免外置功能图顶替真封面。
    final dir = Directory('${root.path}/RJ5555666_内嵌封面作品');
    dir.createSync(recursive: true);
    // 外层目录放一张与封面无关的功能图（命名不含 cover/front/album）
    createPngCover('${dir.path}/トラックリスト.png');
    // 第一首带内嵌封面 APIC + 专辑艺术家（TPE2）；第二首仅文本标签
    createTaggedMp3WithCover('${dir.path}/01 第一首.mp3',
        title: '第一首',
        album: '内嵌封面专辑',
        artist: '曲目艺人A',
        albumArtist: '社团甲',
        trackNumber: 1);
    createTaggedMp3('${dir.path}/02 第二首.mp3',
        title: '第二首',
        album: '内嵌封面专辑',
        artist: '曲目艺人B',
        albumArtist: '社团甲',
        trackNumber: 2);

    final albums = await scanPath(root.path);

    expect(albums.single.localCover, startsWith('data:image/jpeg'),
        reason: '第一首内嵌封面优先于外置功能图');
    // 艺术家与会同 albumArtist 均来自首个含标签音轨（TPE2 优先）
    expect(albums.single.artist, '社团甲', reason: '专辑艺术家(TPE2)优先于曲目艺人');
    expect(albums.single.albumArtist, '社团甲', reason: 'albumArtist 不应再恒为空');
  });

  test('标题清洗：TALB 带换行/重复 → 只取首行并去空白', () async {
    final dir = Directory('${root.path}/tagged_title');
    dir.createSync();
    // 模拟 DLsite 常见 TALB 写入重复 + 换行
    createTaggedMp3('${dir.path}/01.mp3',
        title: '第一首',
        album: '懒散插入。Checkmate\n懒散插入。Checkmate\n\n\n',
        artist: '社团X');

    final albums = await scanPath(root.path);
    expect(albums.single.title, '懒散插入。Checkmate',
        reason: '标题应清洗掉换行与重复，只保留首行');
    expect(albums.single.title.contains('\n'), isFalse);
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
