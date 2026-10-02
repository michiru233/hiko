import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/backup.dart';
import 'package:hiko/models/album.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Album album(String id, {String title = '测试专辑'}) => Album(
        id: id,
        sourcePath: 'file:///tmp/$id',
        title: title,
        rjCode: id,
        favorite: true,
        rating: 4,
        played: 123.5,
        date: DateTime(2026, 10, 2),
      );

  group('HikoBackup.capture', () {
    test('捕获 hiko-* 设置键，排除令牌/路径/分类键；分类单独成字段', () async {
      SharedPreferences.setMockInitialValues({
        'hiko-volume': 0.8,
        'hiko-theme': 'dark',
        'hiko-online-token': 'jwt-secret',
        'hiko-music-folders': <String>['/tmp/music'],
        'hiko-background-path': '/tmp/bg.jpg',
        'hiko-custom-categories': '[{"name":"ASMR"}]',
        'flutter.otherKey': 'ignored',
        'hiko-online-search-history': <String>['RJ123'],
      });

      final backup = await HikoBackup.capture(albums: [album('RJ1')]);

      expect(backup.settings.keys, containsAll(['hiko-volume', 'hiko-theme']));
      expect(backup.settings.keys,
          everyElement(isNot(anyOf('hiko-online-token', 'hiko-music-folders', 'hiko-background-path', 'hiko-custom-categories'))));
      expect(backup.settings, isNot(contains('flutter.otherKey')));
      expect(backup.categories, [{'name': 'ASMR'}]);
      expect(backup.albums.single.id, 'RJ1');
    });
  });

  group('HikoBackup.encode/decode', () {
    test('往返：专辑/分类/设置原样还原', () async {
      SharedPreferences.setMockInitialValues({
        'hiko-volume': 0.65,
        'hiko-show-online-tags': true,
        'hiko-online-page-size': 24,
      });
      final backup = await HikoBackup.capture(albums: [album('RJ1'), album('RJ2', title: '第二张')]);

      final restored = HikoBackup.decode(backup.encode());

      expect(restored.schemaVersion, HikoBackup.currentSchemaVersion);
      expect(restored.albums.length, 2);
      expect(restored.albums[1].title, '第二张');
      expect(restored.albums[0].favorite, isTrue);
      expect(restored.albums[0].rating, 4);
      expect(restored.albums[0].played, 123.5);
      expect(restored.settings['hiko-volume'], 0.65);
      expect(restored.settings['hiko-show-online-tags'], isTrue);
      expect(restored.settings['hiko-online-page-size'], 24);
    });

    test('损坏 JSON 与错误版本拒绝导入，错误信息可读', () {
      expect(() => HikoBackup.decode('not-json{{{'),
          throwsA(isA<BackupFormatException>()));
      expect(() => HikoBackup.decode('{"schemaVersion": 99}'),
          throwsA(isA<BackupFormatException>()));
      expect(() => HikoBackup.decode('"just a string"'),
          throwsA(isA<BackupFormatException>()));
    });
  });

  group('HikoBackup.restoreToPrefs', () {
    test('按值类型写回键，分类写回独立键，返回键数', () async {
      SharedPreferences.setMockInitialValues({});
      final backup = HikoBackup(
        createdAt: DateTime(2026, 10, 2),
        albums: const [],
        categories: [
          {'name': 'ASMR', 'color': '#ff0000'},
        ],
        settings: {
          'hiko-volume': 0.9,
          'hiko-theme': 'dark',
          'hiko-online-page-size': 30,
          'hiko-show-online-tags': true,
          'hiko-online-search-history': ['RJ1', 'RJ2'],
          'unsupported-object': DateTime(2026), // 非白名单类型 → 跳过
        },
      );

      final count = await backup.restoreToPrefs();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('hiko-volume'), 0.9);
      expect(prefs.getString('hiko-theme'), 'dark');
      expect(prefs.getInt('hiko-online-page-size'), 30);
      expect(prefs.getBool('hiko-show-online-tags'), isTrue);
      expect(prefs.getStringList('hiko-online-search-history'), ['RJ1', 'RJ2']);
      expect(prefs.getString('hiko-custom-categories'),
          '[{"name":"ASMR","color":"#ff0000"}]');
      expect(prefs.get('unsupported-object'), isNull);
      expect(count, 5);
    });

    test('restore 后 capture 往返一致（含分类）', () async {
      SharedPreferences.setMockInitialValues({
        'hiko-volume': 0.5,
        'hiko-custom-categories': '[{"name":"治愈系"}]',
      });
      final backup = await HikoBackup.capture(albums: [album('RJ9')]);
      SharedPreferences.setMockInitialValues({}); // 模拟换机空库
      await backup.restoreToPrefs();
      final again = await HikoBackup.capture(albums: const []);

      expect(again.settings['hiko-volume'], 0.5);
      expect(again.categories, [
        {'name': '治愈系'}
      ]);
    });
  });
}
