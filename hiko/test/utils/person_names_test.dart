import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/utils/person_names.dart';

void main() {
  test('1.77 同款分隔符全集：顿号/逗号/斜杠/分号均拆分', () {
    expect(splitVoiceNames('餅梨あむ、花 Christians'), ['餅梨あむ', '花 Christians']);
    expect(splitVoiceNames('ありのりあ,恋鈴桃歌'), ['ありのりあ', '恋鈴桃歌']);
    expect(splitVoiceNames('かの仔／まあ油るる'), ['かの仔', 'まあ油るる']);
    expect(splitVoiceNames('小花衣こっこ/雲八はち'), ['小花衣こっこ', '雲八はち']);
    expect(splitVoiceNames('X；Y；Z'), ['X', 'Y', 'Z']);
  });

  test('去首尾空白并滤空项（分隔符连用/尾分隔符不产生空名）', () {
    expect(splitVoiceNames(' あ · 、 b ,'), ['あ ·', 'b']);
    expect(splitVoiceNames('a,,b'), ['a', 'b']);
  });

  test('单人（无分隔符）原样返回；空串返回空列表', () {
    expect(splitVoiceNames('涼花みなせ'), ['涼花みなせ']);
    expect(splitVoiceNames(''), isEmpty);
  });
}
