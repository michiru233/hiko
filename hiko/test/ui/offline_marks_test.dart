import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/offline_downloads.dart';
import 'package:hiko/data/online/online_audio_cache.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/ui/widgets/online_detail_panel.dart';

/// 离线状态的可见性（1.99.54）：
///
/// - 详情页标题下：已离线 / 下载中 x% / 排队中 / 失败的**状态胶囊**；
/// - 曲目行尾部：已离线（primary，下载完成箭头）/ 已缓存（中性，循环箭头）。
///
/// 两个标记互斥：离线文件同样落在缓存目录里（`isCached` 也会是 true），
/// 所以判序必须「先离线、再缓存」，否则永不被清的那份会被标成可能被清。
void main() {
  final nodes = <Map<String, dynamic>>[
    {'type': 'audio', 'title': 'a.mp3', 'hash': '1/1', 'duration': 60},
    {'type': 'audio', 'title': 'b.mp3', 'hash': '1/2', 'duration': 60},
  ];

  OnlineDetail detail() => OnlineDetail(
    work: OnlineWork.fromJson(<String, dynamic>{
      'id': 1,
      'title': '作品',
      'source_id': 'RJ01657200',
    }),
    tracks: KikoeruClient.parseTrackTree(nodes),
    tree: KikoeruClient.parseTrackNodes(
      nodes,
      KikoeruClient.parseTrackTree(nodes),
    ),
  );

  OfflineWorkEntry offlineEntry() => OfflineWorkEntry(
    workId: 1,
    title: '作品',
    circleName: '',
    coverUrl: '',
    addedAt: DateTime(2026),
    files: const {
      '1/1': OfflineFileEntry(kind: 'audio', size: 1000, title: 'a.mp3'),
    },
  );

  /// 建一个只含 `fileName` 的缓存目录（同步 I/O：testWidgets 跑在 FakeAsync 里，
  /// 真实 await 的 Future 不会推进，必须用同步版本或 tester.runAsync）
  Directory cacheDirWith(String fileName) {
    final dir = Directory.systemTemp.createTempSync('hiko-cache-test');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    File('${dir.path}/$fileName').writeAsBytesSync(List<int>.filled(64, 0));
    return dir;
  }

  /// 缓存 init 走真实文件 IO，要放进 runAsync 才会完成
  Future<OnlineAudioCache> readyCache(
    WidgetTester tester,
    Directory dir,
  ) async {
    final cache = OnlineAudioCache(directory: dir);
    await tester.runAsync(cache.init);
    return cache;
  }

  Future<void> pump(
    WidgetTester tester, {
    List<OfflineWorkEntry> offline = const [],
    Map<int, WorkDownloadState> states = const {},
    required OnlineAudioCache cache,
  }) async {
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onlineClientProvider.overrideWith(
            (ref) => KikoeruClient(baseUrl: 'https://api.asmr.one'),
          ),
          onlineDetailProvider(1).overrideWith((ref) async => detail()),
          offlineIndexListProvider.overrideWith(
            (ref) => _SeededOffline(offline),
          ),
          offlineDownloadProvider.overrideWith(
            (ref) => _SeededDownloads(ref, states),
          ),
          onlineAudioCacheProvider.overrideWith((ref) => cache),
        ],
        child: const MaterialApp(
          home: Scaffold(body: OnlineDetailBody(workId: 1)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('已离线：标题下有胶囊，曲目行是「下载完成」标记', (tester) async {
    final cache = await readyCache(tester, cacheDirWith('1_2.mp3'));

    await pump(tester, offline: [offlineEntry()], cache: cache);

    expect(find.textContaining('已离线 · 1 轨'), findsOneWidget);
    expect(find.byTooltip('已离线下载（不会被自动清理）'), findsOneWidget);
    expect(find.byTooltip('已缓存（空间不足时可能被清理）'), findsOneWidget);
  });

  testWidgets('下载中：胶囊显示字节进度，且不出现「已离线」胶囊', (tester) async {
    final cache = await readyCache(tester, cacheDirWith('1_2.mp3'));

    await pump(
      tester,
      states: const {
        1: DownloadRunning(
          title: '作品',
          coverUrl: '',
          files: [
            FileDownloadProgress(
              hash: '1/1',
              title: 'a.mp3',
              size: 100,
              phase: FileDownloadPhase.done,
              received: 100,
            ),
            FileDownloadProgress(
              hash: '1/2',
              title: 'b.mp3',
              size: 100,
              phase: FileDownloadPhase.running,
              received: 50,
            ),
          ],
        ),
      },
      cache: cache,
    );

    expect(find.textContaining('下载中 75% · 1/2 文件'), findsOneWidget);
    expect(find.textContaining('已离线 ·'), findsNothing);
    // 动作按钮只表达动作，状态不重复
    expect(find.text('取消下载'), findsOneWidget);
  });
}

class _SeededOffline extends OfflineIndexNotifier {
  _SeededOffline(List<OfflineWorkEntry> works) : super(OfflineIndex()) {
    state = works;
  }
}

class _SeededDownloads extends OfflineDownloadService {
  // ignore: use_super_parameters —— 父类构造参数是私有字段 `_ref`，不能写成 super._
  _SeededDownloads(Ref ref, Map<int, WorkDownloadState> initial) : super(ref) {
    state = initial;
  }
}
