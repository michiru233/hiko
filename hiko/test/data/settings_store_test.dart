import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/playback/gain_chain.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('音乐目录：添加去重 + 持久化往返', () async {
    final notifier = SettingsNotifier();
    await notifier.load();

    await notifier.addMusicFolder('/music/dir1');
    await notifier.addMusicFolder('/music/dir2');
    await notifier.addMusicFolder('/music/dir1'); // 去重

    expect(notifier.state.musicFolders, ['/music/dir1', '/music/dir2']);

    // 重新加载（模拟重启）
    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.musicFolders, ['/music/dir1', '/music/dir2']);

    await reloaded.removeMusicFolder('/music/dir1');
    expect(reloaded.state.musicFolders, ['/music/dir2']);
  });

  test('音频增益：默认 1.0 + 设置范围限制与持久化往返', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.audioGain, 1.0);

    // macOS 上限 1.3（底层缺音量滤镜），Windows 上限 4.0；用平台上限断言更健壮
    final cap = desktopGainCap();
    final midGain = cap >= 2.0 ? 2.0 : (cap - 0.1).clamp(1.0, cap);

    // 设置一个合法的中间增益
    await notifier.setAudioGain(midGain);
    expect(notifier.state.audioGain, midGain);

    // 重新加载（模拟重启）
    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.audioGain, midGain);

    // 边界限制：低于下限吸附 1.0，高于上限吸附上限
    await notifier.setAudioGain(0.5);
    expect(notifier.state.audioGain, 1.0);

    await notifier.setAudioGain(5.0);
    expect(notifier.state.audioGain, cap);
  });

  test('播放倍速:默认 1.0 + 0.5/1.0/2.0 持久化往返 + 范围限制', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.playbackRate, 1.0);

    // 0.5 / 1.0 / 2.0 依次设置并逐一验证重启往返
    for (final rate in [0.5, 1.0, 2.0]) {
      await notifier.setPlaybackRate(rate);
      expect(notifier.state.playbackRate, rate);
      final reloaded = SettingsNotifier();
      await reloaded.load();
      expect(reloaded.state.playbackRate, rate);
    }

    // 边界限制 0.5 ~ 2.0
    await notifier.setPlaybackRate(0.2);
    expect(notifier.state.playbackRate, 0.5);
    await notifier.setPlaybackRate(3.0);
    expect(notifier.state.playbackRate, 2.0);
  });

  test('专辑排序：空 prefs 默认 artist_asc', () async {
    final notifier = SettingsNotifier();
    expect(notifier.state.albumSort, 'artist_asc');

    await notifier.load();
    expect(notifier.state.albumSort, 'artist_asc');
  });

  test('专辑排序：设置 title_asc 并重启 load 持久化往返', () async {
    final notifier = SettingsNotifier();
    await notifier.load();

    await notifier.setAlbumSort('title_asc');
    expect(notifier.state.albumSort, 'title_asc');

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.albumSort, 'title_asc');
  });

  test('专辑排序：非法值（空串或未知键）回退 artist_asc', () async {
    SharedPreferences.setMockInitialValues({'hiko-album-sort': 'invalid_key_xyz'});
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.albumSort, 'artist_asc');

    // 运行时传入非法值也安全回退
    await notifier.setAlbumSort('');
    expect(notifier.state.albumSort, 'artist_asc');

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.albumSort, 'artist_asc');
  });

  test('快进/快退步长：空 prefs 默认 3 秒', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.seekStepSeconds, 3);
  });

  test('快进/快退步长：设置 10 秒并重启 load 持久化往返', () async {
    final notifier = SettingsNotifier();
    await notifier.load();

    await notifier.setSeekStep(10);
    expect(notifier.state.seekStepSeconds, 10);

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.seekStepSeconds, 10);
  });

  test('快进/快退步长：白名单外（7 秒）回退 3 秒', () async {
    SharedPreferences.setMockInitialValues({'hiko-seek-step': 7.0});
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.seekStepSeconds, 3);

    // 运行时传入白名单外的值也回退
    await notifier.setSeekStep(99);
    expect(notifier.state.seekStepSeconds, 3);
  });

  test('1.43 显示刮削标签：默认 false + 开启持久化往返', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.showScrapedTags, isFalse, reason: '默认关闭');

    await notifier.setShowScrapedTags(true);
    expect(notifier.state.showScrapedTags, isTrue);

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.showScrapedTags, isTrue);
  });

  test('1.43 每行专辑数：默认 0=自动 + 档位持久化往返 + 白名单外回退自动', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.gridColumns, 0, reason: '默认自动');

    await notifier.setGridColumns(6);
    expect(notifier.state.gridColumns, 6);

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.gridColumns, 6);

    // 1.79 白名单补 2/3 档
    await notifier.setGridColumns(2);
    expect(notifier.state.gridColumns, 2);
    await notifier.setGridColumns(3);
    expect(notifier.state.gridColumns, 3);

    // 白名单外（9、99）回退 0=自动
    await notifier.setGridColumns(9);
    expect(notifier.state.gridColumns, 0);
    await notifier.setGridColumns(99);
    expect(notifier.state.gridColumns, 0);

    // prefs 里存了白名单外值，load 也回退
    SharedPreferences.setMockInitialValues({'hiko-grid-columns': 9.0});
    final bad = SettingsNotifier();
    await bad.load();
    expect(bad.state.gridColumns, 0);
  });

  test('1.54 移动端每行专辑数：默认 2 + 档位持久化往返 + 白名单外回退 2，与桌面档位独立', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.mobileGridColumns, 2, reason: '默认 2');
    expect(notifier.state.gridColumns, 0, reason: '桌面档位不受影响');

    await notifier.setMobileGridColumns(3);
    expect(notifier.state.mobileGridColumns, 3);

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.mobileGridColumns, 3);

    // 白名单外（1、5、9）回退 2
    await notifier.setMobileGridColumns(5);
    expect(notifier.state.mobileGridColumns, 2);

    SharedPreferences.setMockInitialValues({'hiko-mobile-grid-columns': 9.0});
    final bad = SettingsNotifier();
    await bad.load();
    expect(bad.state.mobileGridColumns, 2);
  });

  test('1.84 背景图：默认未启用 + 参数往返与夹取 + 文件丢失回退空路径', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.backgroundPath, '', reason: '默认未启用');
    expect(notifier.state.backgroundBlur, 12);
    expect(notifier.state.backgroundOpacity, 0.65);

    // 参数夹取：blur 0-30，opacity 0-1
    await notifier.setBackgroundBlur(50);
    expect(notifier.state.backgroundBlur, 30);
    await notifier.setBackgroundBlur(-1);
    expect(notifier.state.backgroundBlur, 0);
    await notifier.setBackgroundOpacity(2.0);
    expect(notifier.state.backgroundOpacity, 1.0);
    await notifier.setBackgroundBlur(18);
    await notifier.setBackgroundOpacity(0.8);

    // 真实存在的文件路径可持久化往返
    final tmp = File(
      '${Directory.systemTemp.createTempSync('hiko-bg').path}${Platform.pathSeparator}bg.png',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() {
      try {
        tmp.parent.deleteSync(recursive: true);
      } catch (_) {}
    });
    await notifier.setBackgroundImage(tmp.path);

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.backgroundPath, tmp.path);
    expect(reloaded.state.backgroundBlur, 18);
    expect(reloaded.state.backgroundOpacity, 0.8);

    // 文件已被清理 → load 静默回退空路径（未启用）
    tmp.deleteSync();
    final missing = SettingsNotifier();
    await missing.load();
    expect(missing.state.backgroundPath, '');
  });

  // ------------------------------------------------------------ 1.96.0 在线外观（1.97.0 起改无极滑杆）

  test('1.97.0 标签字号：默认 11 + 范围 clamp 8–18（旧档位全兼容）', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.tagFontSize, 11,
        reason: '默认 11（1.94.0 之前是硬编码的 9）');

    // 1.97.0 起是连续值：范围内任意值原样往返
    for (final size in [8.0, 9.5, 11.0, 13.2, 18.0]) {
      await notifier.setTagFontSize(size);
      expect(notifier.state.tagFontSize, size, reason: '$size 在范围内应原样保留');
    }

    // 1.96.0 的旧档位必须原样保留 —— 老用户升级后观感不变
    for (final legacy in [9.0, 10.0, 12.0, 14.0]) {
      await notifier.setTagFontSize(legacy);
      expect(notifier.state.tagFontSize, legacy, reason: '旧档位 $legacy 应兼容');
    }

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.tagFontSize, 14, reason: '最后一次设的是 14');

    // 范围外 clamp 到边界（不再是「回退默认」：滑杆的语义是连续范围）
    await notifier.setTagFontSize(0.0);
    expect(notifier.state.tagFontSize, 8, reason: '低于下限夹到 8');
    await notifier.setTagFontSize(99.0);
    expect(notifier.state.tagFontSize, 18, reason: '高于上限夹到 18');

    SharedPreferences.setMockInitialValues({
      'hiko-online-tag-font-size': 99.0,
    });
    final badPrefs = SettingsNotifier();
    await badPrefs.load();
    expect(badPrefs.state.tagFontSize, 18, reason: 'load 也要 clamp');
  });

  test('1.97.0 卡片与详情文字倍率：默认 1.0 + 两组互不影响 + 范围 clamp 0.75–1.60', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.onlineCardTextScale, 1.0);
    expect(notifier.state.onlineDetailTextScale, 1.0);

    await notifier.setOnlineCardTextScale(1.3);
    expect(notifier.state.onlineCardTextScale, 1.3);
    expect(notifier.state.onlineDetailTextScale, 1.0, reason: '两组各自独立');

    await notifier.setOnlineDetailTextScale(0.85);
    expect(notifier.state.onlineDetailTextScale, 0.85);
    expect(notifier.state.onlineCardTextScale, 1.3, reason: '改详情不该动卡片');

    // 1.97.0 起连续值：范围内任意值往返（含旧档位之外的 1.05 ——
    // 它在 1.96 是白名单外会被回退，1.97 起是合法的连续值）
    await notifier.setOnlineCardTextScale(1.05);
    expect(notifier.state.onlineCardTextScale, 1.05, reason: '连续值原样保留');
    await notifier.setOnlineDetailTextScale(1.42);
    expect(notifier.state.onlineDetailTextScale, 1.42);

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.onlineCardTextScale, 1.05);
    expect(reloaded.state.onlineDetailTextScale, 1.42);

    // 范围外 clamp 到边界
    await notifier.setOnlineCardTextScale(0.5);
    expect(notifier.state.onlineCardTextScale, 0.75, reason: '低于下限夹到 0.75');
    await notifier.setOnlineDetailTextScale(2.0);
    expect(notifier.state.onlineDetailTextScale, 1.60, reason: '高于上限夹到 1.60');

    SharedPreferences.setMockInitialValues({
      'hiko-online-card-text-scale': 3.0,
    });
    final badPrefs = SettingsNotifier();
    await badPrefs.load();
    expect(badPrefs.state.onlineCardTextScale, 1.60, reason: 'load 也要 clamp');
  });

  test('1.97.0 曲目标题字号：默认 12 + 范围 clamp 10–20 + 与详情倍率独立存储', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.onlineTrackTitleFontSize, 12, reason: '默认与旧基准一致');

    await notifier.setOnlineTrackTitleFontSize(15.5);
    expect(notifier.state.onlineTrackTitleFontSize, 15.5);
    await notifier.setOnlineDetailTextScale(1.3);
    expect(notifier.state.onlineTrackTitleFontSize, 15.5,
        reason: '改详情倍率不该连带标题字号');

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.onlineTrackTitleFontSize, 15.5);

    await notifier.setOnlineTrackTitleFontSize(5.0);
    expect(notifier.state.onlineTrackTitleFontSize, 10, reason: '低于下限夹到 10');
    await notifier.setOnlineTrackTitleFontSize(30.0);
    expect(notifier.state.onlineTrackTitleFontSize, 20, reason: '高于上限夹到 20');
  });

  test('1.97.0 在线每页条数：默认 20 + 档位白名单 20/60/100 + 落盘', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.onlinePageSize, 20);

    for (final size in SettingsNotifier.validOnlinePageSizes) {
      await notifier.setOnlinePageSize(size);
      expect(notifier.state.onlinePageSize, size);
    }

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.onlinePageSize, 100,
        reason: '最后一次设的是 100 —— 选择要能重启恢复');

    for (final bad in [0.0, 40.0, 500.0]) {
      await notifier.setOnlinePageSize(bad);
      expect(notifier.state.onlinePageSize, 20, reason: '$bad 不在档位里，回退默认 20');
    }

    SharedPreferences.setMockInitialValues({
      'hiko-online-page-size': 60.0,
    });
    final saved = SettingsNotifier();
    await saved.load();
    expect(saved.state.onlinePageSize, 60, reason: 'load 读回持久化值');
  });

  test('1.96.0 在线每行卡片数：默认 0=自动 + 档位往返 + 白名单外回退，与主界面档位独立', () async {
    final notifier = SettingsNotifier();
    await notifier.load();
    expect(notifier.state.onlineGridColumns, 0, reason: '默认自动');
    expect(notifier.state.gridColumns, 0);

    await notifier.setOnlineGridColumns(6);
    expect(notifier.state.onlineGridColumns, 6);
    expect(notifier.state.gridColumns, 0, reason: '主界面档位不该被连带改动');

    await notifier.setGridColumns(5);
    expect(notifier.state.gridColumns, 5);
    expect(notifier.state.onlineGridColumns, 6, reason: '反向也不该联动');

    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.onlineGridColumns, 6);

    // 白名单外回退自动。注意 **2 也是白名单外** —— 移动端「2 列」是「自动」的
    // 既定行为，不是一个可选项（1.96.0 裁决 Q4：只给 3–8 六档 + 自动）
    for (final bad in [1.0, 2.0, 9.0, 99.0]) {
      await notifier.setOnlineGridColumns(bad);
      expect(notifier.state.onlineGridColumns, 0, reason: '$bad 不在档位里');
    }
  });
}
