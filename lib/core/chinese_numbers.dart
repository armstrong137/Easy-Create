/// 中文数字与章节默认命名（大纲树自动标注用）
library;

const _digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

/// 1~99 转中文数字（大纲章节数足够；超界返回阿拉伯数字兜底）
String toChineseNumber(int n) {
  if (n <= 0 || n > 99) return '$n';
  if (n < 10) return _digits[n];
  final tens = n ~/ 10;
  final ones = n % 10;
  final tensPart = tens == 1 ? '十' : '${_digits[tens]}十';
  return ones == 0 ? tensPart : '$tensPart${_digits[ones]}';
}

/// 第 [index]（从 0 起）个章的默认标题：引子 → 第一章 → 第二章 …
/// （假设，待终审：首章为"引子"）
String defaultChapterTitle(int index) =>
    index == 0 ? '引子' : '第${toChineseNumber(index)}章';

/// 第 [index]（从 0 起）个节的默认标题：第一节 → 第二节 …
String defaultSectionTitle(int index) => '第${toChineseNumber(index + 1)}节';
