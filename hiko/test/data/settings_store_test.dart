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
}
