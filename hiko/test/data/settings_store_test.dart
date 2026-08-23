import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
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

    // 设置增益 2.0x
    await notifier.setAudioGain(2.0);
    expect(notifier.state.audioGain, 2.0);

    // 重新加载（模拟重启）
    final reloaded = SettingsNotifier();
    await reloaded.load();
    expect(reloaded.state.audioGain, 2.0);

    // 边界限制 1.0 ~ 4.0
    await notifier.setAudioGain(0.5);
    expect(notifier.state.audioGain, 1.0);

    await notifier.setAudioGain(5.0);
    expect(notifier.state.audioGain, 4.0);
  });
}
