import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/content_font.dart';

/// 灵感文本按语言选字体（中文楷体 / 英文品牌斜体）
void main() {
  group('contentFontFamily', () {
    test('纯中文 → 楷体（返回 null 落全局默认）', () {
      expect(contentFontFamily('深夜地铁站遇见卖橘子的老人'), isNull);
      expect(contentFontFamily('第十三个月亮。'), isNull);
    });

    test('纯英文 → 品牌字体', () {
      expect(contentFontFamily('Midnight metro, orange seller'),
          'EasyCreateBrand');
      expect(contentFontFamily('The Thirteenth Moon'), 'EasyCreateBrand');
    });

    test('中英混排含中文 → 楷体（正文体优先）', () {
      expect(contentFontFamily('深夜的 metro'), isNull);
      expect(contentFontFamily('a 老人 b'), isNull);
    });

    test('纯数字/符号/空 → 楷体（不算英文灵感）', () {
      expect(contentFontFamily('12345'), isNull);
      expect(contentFontFamily('!!! ??? 。。。'), isNull);
      expect(contentFontFamily(''), isNull);
    });

    test('英文带标点数字仍算英文', () {
      expect(contentFontFamily('Chapter 1: the beginning.'),
          'EasyCreateBrand');
    });

    test('contentUsesBrandFont 与 family 一致', () {
      expect(contentUsesBrandFont('Hello world'), isTrue);
      expect(contentUsesBrandFont('你好世界'), isFalse);
      expect(contentUsesBrandFont('123'), isFalse);
    });
  });

  group('contentTextStyle（方案 A 全局文字体系）', () {
    test('西文内容：品牌衬线斜体', () {
      final s = contentTextStyle(text: 'Midnight metro', fontSize: 16);
      expect(s.fontFamily, 'EasyCreateBrand');
      expect(s.fontStyle, FontStyle.italic);
    });

    test('中文内容：楷体且**绝不斜体**（Cormorant 无汉字，斜体会变假斜体歪楷字）', () {
      for (final t in ['山海之外', '深夜的 metro', '第十三个月亮。']) {
        final s = contentTextStyle(text: t, fontSize: 16);
        expect(s.fontFamily, 'LXGWWenKai', reason: t);
        expect(s.fontStyle, FontStyle.normal, reason: t);
      }
    });

    test('纯数字走楷体正体（星球名常见 "1"）', () {
      final s = contentTextStyle(text: '1', fontSize: 21);
      expect(s.fontFamily, 'LXGWWenKai');
      expect(s.fontStyle, FontStyle.normal);
    });

    test('默认字距按语言给：中文更透气，衬线斜体只补一点', () {
      expect(contentTextStyle(text: '山海', fontSize: 16).letterSpacing, 1.0);
      expect(contentTextStyle(text: 'Sea', fontSize: 16).letterSpacing, 0.4);
      // 显式传入可覆盖（星球名要更舒展）
      expect(
        contentTextStyle(text: '山海', fontSize: 21, letterSpacing: 1.2)
            .letterSpacing,
        1.2,
      );
    });

    test('颜色/字重/阴影原样透传', () {
      const c = Color(0xFF123456);
      final s = contentTextStyle(
        text: 'abc',
        fontSize: 12,
        color: c,
        fontWeight: FontWeight.w300,
        shadows: const [Shadow(blurRadius: 4)],
      );
      expect(s.color, c);
      expect(s.fontWeight, FontWeight.w300);
      expect(s.shadows, hasLength(1));
    });
  });
}
