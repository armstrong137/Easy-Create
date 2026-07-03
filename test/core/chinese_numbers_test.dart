import 'package:flutter_test/flutter_test.dart';

import 'package:novel_app/core/chinese_numbers.dart';

/// 中文数字与章节默认命名
void main() {
  test('中文数字 1~99', () {
    expect(toChineseNumber(1), '一');
    expect(toChineseNumber(10), '十');
    expect(toChineseNumber(11), '十一');
    expect(toChineseNumber(20), '二十');
    expect(toChineseNumber(35), '三十五');
    expect(toChineseNumber(99), '九十九');
  });

  test('章默认命名：引子 → 第一章 → 第二章', () {
    expect(defaultChapterTitle(0), '引子');
    expect(defaultChapterTitle(1), '第一章');
    expect(defaultChapterTitle(2), '第二章');
    expect(defaultChapterTitle(12), '第十二章');
  });

  test('节默认命名：第一节起', () {
    expect(defaultSectionTitle(0), '第一节');
    expect(defaultSectionTitle(4), '第五节');
  });
}
