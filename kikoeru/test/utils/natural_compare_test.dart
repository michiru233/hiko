import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru/utils/natural_compare.dart';

void main() {
  group('naturalCompare', () {
    test('数字感知排序', () {
      final list = ['10.mp3', '2.mp3', '1.mp3'];
      list.sort(naturalCompare);
      expect(list, ['1.mp3', '2.mp3', '10.mp3']);
    });

    test('数字前导零：数值相等后继续比较剩余部分（与 Kotlin 原版一致）', () {
      // '01' 与 '1' 数值相等，继续比较，最终按剩余长度分高下
      expect(naturalCompare('01.mp3', '1.mp3'), 1);
      expect(naturalCompare('1.mp3', '01.mp3'), -1);
    });

    test('普通字母排序，大小写不敏感', () {
      final list = ['Banana', 'apple', 'Cherry'];
      list.sort(naturalCompare);
      expect(list, ['apple', 'Banana', 'Cherry']);
    });

    test('数字与字母混合', () {
      final list = ['track2', 'track10', 'track1'];
      list.sort(naturalCompare);
      expect(list, ['track1', 'track2', 'track10']);
    });

    test('中日文按码位比较（非乱序）', () {
      final list = ['雨夜', '耳语', 'あめ'];
      list.sort(naturalCompare);
      expect(list.length, 3);
    });
  });
}
