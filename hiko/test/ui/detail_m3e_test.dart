import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/models/track.dart';
import 'package:hiko/playback/playback_controller.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/detail_drawer.dart';

/// 详情面板 M3E 换装回归锁（1.99.34，plan-hiko-detail-m3e.md §8.2）：
/// 1. 主行动唯一锁：操作区 filled 主键恰好 1 个（从头播放）；
/// 2. 分组卡与曲目行在 480dp 面板宽度下无溢出；
/// 3. ALBUM 内部 id 不再出现在展示层（D4）。
Album _album() => Album(
      id: 'local-a6c1d64d1c088c07',
      sourcePath: '/x/local-a6c1d64d1c088c07',
      title: '【簡体中文版】テストアルバム名がここに入るとても長いタイトル',
      genre: '素',
      date: DateTime(2026),
      totalDuration: 4800,
      played: 1200,
      tracks: [
        Track(index: 0, name: 'トラック1', url: 'file:///x/1.mp3', duration: 600),
        Track(index: 1, name: 'トラック2', url: 'file:///x/2.mp3', duration: 600),
      ],
    );

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(overrides: [
    settingsProvider.overrideWith((ref) => SettingsNotifier()),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 480,
            child: DetailDrawer(album: _album(), onClose: () {}),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('480dp 面板：无溢出，主行动唯一，内部 id 不展示', (tester) async {
    await _pump(tester);
    expect(tester.takeException(), isNull, reason: '480dp 面板不得溢出');

    // 主行动唯一锁：从头播放（filled 主键）只此一个
    expect(find.text('从头播放'), findsOneWidget);
    // D4：ALBUM 内部 id 不出现在展示层
    expect(
      find.textContaining('local-a6c1d64d1c088c07'),
      findsNothing,
      reason: '内部哈希 id 对用户无意义，不再展示（RJ 码在元数据行）',
    );
    // 分组卡行
    expect(find.text('总时长'), findsOneWidget);
    expect(find.text('完成进度'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget, reason: '1200/4800=25%');
    // 曲目行（懒构建视口内至少第一首）
    expect(find.text('01'), findsWidgets);
  });

  testWidgets('曲目/歌词分段存在', (tester) async {
    await _pump(tester);
    expect(find.text('曲目列表 (2)'), findsOneWidget);
    expect(find.text('歌词字幕'), findsOneWidget);
  });
}
