import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/library_provider.dart';
import 'package:hiko/data/library_store.dart';
import 'package:hiko/models/album.dart';

/// 老库添加时间迁移的落盘锁（1.99.69）。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hiko-date-migration');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Album album(String id, DateTime date) => Album(
        id: id,
        sourcePath: '/tmp/$id',
        title: id,
        date: date,
        tracks: const [],
      );

  Future<File> writeLibrary(
    List<Album> albums, {
    bool withUnknownField = false,
  }) async {
    final list = <Map<String, Object?>>[
      for (final a in albums)
        <String, Object?>{
          ...a.toJson(),
          if (withUnknownField) 'x-keep': 1,
        },
    ];
    final file = File('${tmp.path}/library.json');
    await file.writeAsString(
      jsonEncode(<String, Object?>{'version': 1, 'albums': list}),
    );
    return file;
  }

  List<int> readDates(File file) {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final albums = data['albums'] as List;
    return [
      for (final a in albums) (a as Map<String, dynamic>)['date'] as int,
    ];
  }

  test('load：date<=0 的条目被补齐并写回文件，顺序不变', () async {
    final file = await writeLibrary([
      album('a', DateTime.fromMillisecondsSinceEpoch(0)),
      album('b', DateTime.fromMillisecondsSinceEpoch(0)),
      album('c', DateTime(2026, 1, 1)),
    ]);
    final store = LibraryStore(overrideDir: tmp);
    final notifier = LibraryNotifier(store);

    await notifier.load();

    expect(notifier.state.map((a) => a.id).toList(), ['a', 'b', 'c']);
    expect(notifier.state.every((a) => a.date.millisecondsSinceEpoch > 0), isTrue);
    final persisted = readDates(file);
    expect(persisted.every((v) => v > 0), isTrue, reason: '迁移必须落盘');
    expect(persisted[2], DateTime(2026, 1, 1).millisecondsSinceEpoch);
  });

  test('load：全都有时间时不重写文件（未知字段仍在）', () async {
    final file = await writeLibrary([
      album('a', DateTime(2026, 1, 1)),
      album('b', DateTime(2026, 2, 1)),
    ], withUnknownField: true);
    final before = file.readAsStringSync();

    final notifier = LibraryNotifier(LibraryStore(overrideDir: tmp));
    await notifier.load();

    expect(file.readAsStringSync(), before, reason: '没有缺失就不该发生写盘');
    expect(file.readAsStringSync(), contains('x-keep'));
  });

  test('replaceAll（备份恢复）同样补齐并落盘', () async {
    final file = await writeLibrary([album('old', DateTime(2026, 1, 1))]);
    final notifier = LibraryNotifier(LibraryStore(overrideDir: tmp));
    await notifier.load();

    await notifier.replaceAll([
      album('restored', DateTime.fromMillisecondsSinceEpoch(0)),
    ]);

    expect(notifier.state.single.date.millisecondsSinceEpoch, greaterThan(0));
    expect(readDates(file).single, greaterThan(0));
  });

  test('迁移幂等：连续两次 load，第二次不再写文件', () async {
    final file = await writeLibrary([
      album('a', DateTime.fromMillisecondsSinceEpoch(0)),
    ]);
    final store = LibraryStore(overrideDir: tmp);
    await LibraryNotifier(store).load();
    final afterFirst = file.readAsStringSync();

    await LibraryNotifier(LibraryStore(overrideDir: tmp)).load();
    expect(file.readAsStringSync(), afterFirst);
  });
}
