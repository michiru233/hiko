import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/import_service.dart';
import 'package:hiko/data/library_store.dart';

void main() {
  test('多目录批量导入：合并 + id 去重 + 落盘', () async {
    final tmp = Directory.systemTemp.createTempSync('hiko-import-multi');
    addTearDown(() => tmp.deleteSync(recursive: true));

    // 两个源目录各一张专辑（RJ 命名）
    final src1 = Directory('${tmp.path}/src1/RJ11111_专辑A');
    src1.createSync(recursive: true);
    final src2 = Directory('${tmp.path}/src2/RJ22222_专辑B');
    src2.createSync(recursive: true);
    await _createWav('${src1.path}/01.wav', 440, 1);
    await _createWav('${src2.path}/01.wav', 554, 1);

    final store = LibraryStore(overrideDir: Directory('${tmp.path}/data'));
    final service = ImportService(store);

    // 一次导入两个目录
    var progressCalls = 0;
    final albums = await service.importFolders(
      ['${tmp.path}/src1', '${tmp.path}/src2'],
      onProgress: (_) => progressCalls++,
    );
    expect(albums.length, 2);
    expect(albums.map((a) => a.rjCode).toSet(), {'RJ11111', 'RJ22222'});
    expect(progressCalls, greaterThanOrEqualTo(2));

    // 已落盘
    final loaded = await store.load();
    expect(loaded.length, 2);

    // 重复导入同一目录：id 相同覆盖，不产生重复
    final again = await service.importFolders(['${tmp.path}/src1']);
    expect(again.length, 2);
  });
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
    final sample = (7000 * fade * sin(2 * pi * frequency * i / sampleRate)).round();
    buffer.add(_le16(sample));
  }
  final file = File(path);
  await file.writeAsBytes(buffer.toBytes());
}

Uint8List _le16(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF]);
Uint8List _le32(int v) => Uint8List.fromList([
      v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF,
    ]);
