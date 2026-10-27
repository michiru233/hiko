import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/offline_downloads.dart';
import 'package:hiko/ui/screens/downloads_screen.dart';

/// 下载中心（1.99.54）的回归锁。
///
/// 三段固定顺序：进行中 → 失败 → 已完成；进行中的作品逐文件显示阶段，
/// 已完成的作品收成一行。数据来自 `WorkDownloadState`（自带标题/封面），
/// 所以这里直接种状态即可，不经过真实下载器。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    Map<int, WorkDownloadState> states = const {},
    List<OfflineWorkEntry> done = const [],
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          offlineDownloadProvider.overrideWith(
            (ref) => _SeededDownloads(ref, states),
          ),
          offlineIndexListProvider.overrideWith((ref) => _SeededOffline(done)),
        ],
        child: const MaterialApp(home: Scaffold(body: DownloadsScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('空态：还没有离线下载', (tester) async {
    await pump(tester);
    expect(find.text('还没有离线下载'), findsOneWidget);
  });

  testWidgets('进行中：总进度按字节算，逐文件显示阶段', (tester) async {
    await pump(
      tester,
      states: const {
        1: DownloadRunning(
          title: '作品 A',
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
            FileDownloadProgress(hash: '1/3', title: 'c.mp3', size: 100),
          ],
        ),
      },
    );

    expect(find.text('作品 A'), findsOneWidget);
    expect(find.text('1 / 3 文件 · 150 B / 300 B'), findsOneWidget);
    // 卡片右上与当前文件行各一个
    expect(find.text('50%'), findsNWidgets(2));
    expect(find.text('a.mp3'), findsOneWidget);
    expect(find.text('b.mp3'), findsOneWidget);
    expect(find.text('c.mp3'), findsOneWidget);
    expect(find.text('等待'), findsOneWidget);
    expect(find.text('取消下载'), findsOneWidget);
  });

  testWidgets('失败：显示原因与重试', (tester) async {
    await pump(
      tester,
      states: const {2: DownloadFailed('全部文件下载失败，请检查网络', title: '作品 C')},
    );

    expect(find.text('作品 C'), findsOneWidget);
    expect(find.text('全部文件下载失败，请检查网络'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('移除'), findsOneWidget);
  });

  testWidgets('已完成：一行摘要 + 删除要二次确认', (tester) async {
    await pump(
      tester,
      done: [
        OfflineWorkEntry(
          workId: 3,
          title: '作品 B',
          circleName: '',
          coverUrl: '',
          addedAt: DateTime(2026),
          files: const {
            '3/1': OfflineFileEntry(
              kind: 'audio',
              size: 2 * 1024 * 1024,
              title: 'x.mp3',
            ),
          },
        ),
      ],
    );

    expect(find.text('作品 B'), findsOneWidget);
    expect(find.text('已完成 · 1 轨 · 2.0 MB'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除离线内容'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('删除离线内容'), findsNothing);
  });
}

class _SeededDownloads extends OfflineDownloadService {
  // ignore: use_super_parameters —— 父类构造参数是私有字段 `_ref`，不能写成 super._
  _SeededDownloads(Ref ref, Map<int, WorkDownloadState> initial) : super(ref) {
    state = initial;
  }
}

class _SeededOffline extends OfflineIndexNotifier {
  _SeededOffline(List<OfflineWorkEntry> works) : super(OfflineIndex()) {
    state = works;
  }
}
