import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/inspiration_font.dart';

/// 灵感文本按语言选字体（中文楷体 / 英文品牌斜体）
void main() {
  group('inspirationFontFamily', () {
    test('纯中文 → 楷体（返回 null 落全局默认）', () {
      expect(inspirationFontFamily('深夜地铁站遇见卖橘子的老人'), isNull);
      expect(inspirationFontFamily('第十三个月亮。'), isNull);
    });

    test('纯英文 → 品牌字体', () {
      expect(inspirationFontFamily('Midnight metro, orange seller'),
          'EasyCreateBrand');
      expect(inspirationFontFamily('The Thirteenth Moon'), 'EasyCreateBrand');
    });

    test('中英混排含中文 → 楷体（正文体优先）', () {
      expect(inspirationFontFamily('深夜的 metro'), isNull);
      expect(inspirationFontFamily('a 老人 b'), isNull);
    });

    test('纯数字/符号/空 → 楷体（不算英文灵感）', () {
      expect(inspirationFontFamily('12345'), isNull);
      expect(inspirationFontFamily('!!! ??? 。。。'), isNull);
      expect(inspirationFontFamily(''), isNull);
    });

    test('英文带标点数字仍算英文', () {
      expect(inspirationFontFamily('Chapter 1: the beginning.'),
          'EasyCreateBrand');
    });

    test('inspirationIsBrand 与 family 一致', () {
      expect(inspirationIsBrand('Hello world'), isTrue);
      expect(inspirationIsBrand('你好世界'), isFalse);
      expect(inspirationIsBrand('123'), isFalse);
    });
  });
}
