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

    // 白名单外（3、9、99）回退 0=自动
    await notifier.setGridColumns(3);
    expect(notifier.state.gridColumns, 0);
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
}
