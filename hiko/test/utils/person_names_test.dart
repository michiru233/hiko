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

  test('1.87 新增分隔符：反斜杠/竖线/中点均拆分', () {
    // 半角反斜杠（本次报告的形态，标签里最常用）
    expect(splitVoiceNames('柚木つばめ \\ 逢坂成美'), ['柚木つばめ', '逢坂成美']);
    // 全角反斜杠
    expect(splitVoiceNames('柚木つばめ＼逢坂成美'), ['柚木つばめ', '逢坂成美']);
    // 半角/全角竖线
    expect(splitVoiceNames('あむ|ありの'), ['あむ', 'ありの']);
    expect(splitVoiceNames('あむ｜ありの'), ['あむ', 'ありの']);
    // 片假名中点 U+30FB 与半角中点 U+FF65
    expect(splitVoiceNames('柚木つばめ・逢坂成美'), ['柚木つばめ', '逢坂成美']);
    expect(splitVoiceNames('柚木つばめ･逢坂成美'), ['柚木つばめ', '逢坂成美']);
    // 一份标签里混用多种分隔符
    expect(splitVoiceNames('A、B / C；D|E'), ['A', 'B', 'C', 'D', 'E']);
  });

  test('U+00B7 拉丁中点不属于分隔符（名字内部字符，既有约定）', () {
    expect(splitVoiceNames('あ · b'), ['あ · b']);
  });

  test('去首尾空白并滤空项（分隔符连用/尾分隔符不产生空名）', () {
    expect(splitVoiceNames(' あ · 、 b ,'), ['あ ·', 'b']);
    expect(splitVoiceNames('a,,b'), ['a', 'b']);
    expect(splitVoiceNames('柚木つばめ \\\\ 逢坂成美'), ['柚木つばめ', '逢坂成美']);
    expect(splitVoiceNames('柚木つばめ \\'), ['柚木つばめ']);
  });

  test('单人（无分隔符）原样返回；空串返回空列表', () {
    expect(splitVoiceNames('涼花みなせ'), ['涼花みなせ']);
    expect(splitVoiceNames(''), isEmpty);
  });

  test('归一化：分隔符统一成顿号（卡片胶囊/抽屉灰字行用）', () {
    expect(normalizeVoiceSeparators('柚木つばめ \\ 逢坂成美'), '柚木つばめ、逢坂成美');
    expect(normalizeVoiceSeparators('柚木つばめ＼逢坂成美'), '柚木つばめ、逢坂成美');
    expect(normalizeVoiceSeparators('あ|B｜C'), 'あ、B、C');
    expect(normalizeVoiceSeparators('あ・B･C'), 'あ、B、C');
    // 已归一化的串幂等；单人原样；空串返回空串；首尾空白与连用分隔符被压掉
    expect(normalizeVoiceSeparators('あ、B'), 'あ、B');
    expect(normalizeVoiceSeparators('涼花みなせ'), '涼花みなせ');
    expect(normalizeVoiceSeparators(''), '');
    expect(normalizeVoiceSeparators(' あ 、、 B '), 'あ、B');
  });

  test('归一化与拆分同源：归一化结果再拆分仍得到同样的人名', () {
    const raw = '柚木つばめ \\ 逢坂成美';
    expect(splitVoiceNames(normalizeVoiceSeparators(raw)), splitVoiceNames(raw));
  });
}
