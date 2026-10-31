import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/library_snapshots.dart';
import 'package:hiko/data/library_store.dart';

/// 库历史快照（1.99.62）。
///
/// 这里全是**普通 test 而不是 testWidgets**：快照就是文件复制，用
/// `testWidgets` 的 FakeAsync 时钟跑真实 IO 会卡死不返回（见 handoff §4 的坑）。
/// 每个用例自建临时目录，`LibraryStore(overrideDir:)` 指过去，互不干扰。
void main() {
  late Directory dir;
  late LibraryStore store;
  late LibrarySnapshots snapshots;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hiko_snapshot_');
    store = LibraryStore(overrideDir: dir);
    snapshots = LibrarySnapshots(store: store);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  String libraryJson(int albums) =>
      '{"version":1,"albums":[${List.filled(albums, '{"id":"x"}').join(',')}]}';

  Future<File> writeLibrary(int albums) =>
      File('${dir.path}/library.json').writeAsString(libraryJson(albums));

  Future<File> putSnapshot(String name, String content) async {
    final backups = Directory('${dir.path}/${LibrarySnapshots.backupsDirName}');
    if (!backups.existsSync()) await backups.create(recursive: true);
    return File('${backups.path}/$name').writeAsString(content);
  }

  test('capture 复制当前库文件并记下来源', () async {
    await writeLibrary(3);

    final snapshot = await snapshots.capture(reason: 'edit');

    expect(snapshot, isNotNull);
    expect(snapshot!.file.existsSync(), isTrue);
    expect(snapshot.reason, 'edit');
    expect(snapshot.bytes, greaterThan(0));
    expect(await snapshot.albumCount(), 3);

    final list = await snapshots.list();
    expect(list, hasLength(1));
    expect(list.single.fileName, startsWith('library-'));
    expect(list.single.reason, 'edit');
    // 快照就在数据目录下的 library-backups 里，不散落
    expect(
      list.single.file.parent.path,
      endsWith(LibrarySnapshots.backupsDirName),
    );
  });

  test('库文件还不存在时不留快照', () async {
    expect(await snapshots.capture(), isNull);
    expect(await snapshots.list(), isEmpty);
  });

  test('节流：非强制捕获在窗口内只留一份', () async {
    await writeLibrary(2);

    final first = await snapshots.capture(reason: 'edit', force: false);
    final second = await snapshots.capture(reason: 'edit', force: false);

    expect(first, isNotNull);
    expect(second, isNull);
    expect(await snapshots.list(), hasLength(1));

    // 强制捕获不受节流影响（重置数据库这种操作必须留档）
    final forced = await snapshots.capture(reason: 'reset');
    expect(forced, isNotNull);
    expect(await snapshots.list(), hasLength(2));
  });

  test('prune 只保留最新 5 份', () async {
    for (var i = 1; i <= 7; i++) {
      await putSnapshot(
        'library-2026010$i-120000-auto.json',
        libraryJson(i),
      );
    }
    expect(await snapshots.list(), hasLength(7));

    await snapshots.prune();

    final kept = await snapshots.list();
    expect(kept, hasLength(5));
    // 最新的 7、6、5、4、3 留下，最旧的 1、2 被淘汰
    expect(
      kept.map((s) => s.fileName),
      [
        'library-20260107-120000-auto.json',
        'library-20260106-120000-auto.json',
        'library-20260105-120000-auto.json',
        'library-20260104-120000-auto.json',
        'library-20260103-120000-auto.json',
      ],
    );
  });

  test('prune 尊重总量上限，但最新一份永远留着', () async {
    final tight = LibrarySnapshots(
      store: store,
      keepCount: 10,
      maxTotalBytes: 300,
    );
    final blob = '{"version":1,"albums":[]}${' ' * 176}'; // 200 字节
    for (var i = 1; i <= 4; i++) {
      await putSnapshot('library-2026010$i-120000-auto.json', blob);
    }

    await tight.prune();

    final kept = await tight.list();
    // 200 + 200 > 300，所以只留最新那份
    expect(kept, hasLength(1));
    expect(kept.single.fileName, 'library-20260104-120000-auto.json');
  });

  test('restore 覆盖库文件，并先把当前状态再留一份', () async {
    await writeLibrary(3);
    final target = await putSnapshot(
      'library-20260101-120000-auto.json',
      libraryJson(7),
    );
    final snapshot = (await snapshots.list()).first;

    await snapshots.restore(snapshot);

    final restored = await File('${dir.path}/library.json').readAsString();
    expect(restored, libraryJson(7));

    // 恢复前那份「当前状态」在，内容是恢复前的 3 张
    final safety = (await snapshots.list())
        .where((s) => s.reason == 'restore')
        .toList();
    expect(safety, hasLength(1));
    expect(await safety.single.albumCount(), 3);
    expect(target.existsSync(), isTrue, reason: '被用的快照本身不该被删');
  });

  test('restore 拒绝坏快照，且不动当前库', () async {
    await writeLibrary(3);
    final original = await File('${dir.path}/library.json').readAsString();
    await putSnapshot('library-20260101-120000-auto.json', 'not json at all');
    final broken = (await snapshots.list()).first;

    expect(
      () => snapshots.restore(broken),
      throwsA(isA<LibrarySnapshotException>()),
    );

    expect(
      await File('${dir.path}/library.json').readAsString(),
      original,
      reason: '校验失败时不能已经把库覆盖掉',
    );
  });

  test('list 最新在前，并按文件名解析时间', () async {
    await putSnapshot('library-20260101-120000-auto.json', libraryJson(1));
    await putSnapshot('library-20260203-093000-edit.json', libraryJson(2));
    await putSnapshot('library-20251231-235900-auto.json', libraryJson(3));
    // 不是快照命名规则的文件要忽略
    await putSnapshot('notes.txt', 'hi');

    final list = await snapshots.list();

    expect(list.map((s) => s.reason), ['edit', 'auto', 'auto']);
    expect(list.first.createdAt.year, 2026);
    expect(list.first.createdAt.month, 2);
    expect(list.first.createdAt.day, 3);
    expect(list.first.createdAt.hour, 9);
    expect(list.first.createdAt.minute, 30);
    expect(list.last.createdAt.month, 12);
  });

  test('来源标签面向用户', () {
    expect(snapshotReasonLabel('reset'), '重置前');
    expect(snapshotReasonLabel('restore'), '恢复前');
    expect(snapshotReasonLabel('edit'), '编辑');
    expect(snapshotReasonLabel('unknown'), '自动');
  });
}
