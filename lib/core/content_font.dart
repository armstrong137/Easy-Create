/// 全局文字体系（方案 A·品牌衬线延伸）——**内容文本**的唯一出处。
///
/// 规则（用户 2026-07-28 定稿）：
/// - 纯西文（含数字标点，但**不含中日韩汉字**）→ 品牌字体 EasyCreateBrand 斜体，
///   与首页标题 "Create Something" 同族；
/// - 含中文 → 霞鹜文楷**正体**。绝不给中文加斜体：Cormorant 没有汉字字形，
///   强行倾斜会得到"假斜体"的歪楷字（做方案示意图时实测很生硬）。
///
/// 判定用"是否出现 CJK 汉字"而非"是否含拉丁字母"，因为中英混排（如
/// "深夜的 metro"）应保持楷体正文体，只有整条是西文时才用品牌斜体。
///
/// 适用范围＝**用户写出来的内容**：星球名、章/节名、灵感、卡片正文。
/// 界面文字（按钮、对话框、提示、设置项）不走这里——那些以中文为主，
/// 统一由全局主题的楷体承接，强行斜体反而伤可读性。
library;

import 'package:flutter/painting.dart';

/// CJK 统一表意文字区间（含扩展 A、兼容表意）——覆盖常用中文
bool _hasCjk(String s) {
  for (final r in s.runes) {
    if ((r >= 0x4E00 && r <= 0x9FFF) || // CJK 统一表意
        (r >= 0x3400 && r <= 0x4DBF) || // 扩展 A
        (r >= 0xF900 && r <= 0xFAFF) || // 兼容表意
        (r >= 0x3000 && r <= 0x303F)) {
      // CJK 标点（。！、等）
      return true;
    }
  }
  return false;
}

/// 是否至少含一个拉丁字母（纯符号/数字不算"西文内容"）
bool _hasLatinLetter(String s) {
  for (final r in s.runes) {
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return true;
  }
  return false;
}

/// 内容 → 字体族名；null 表示用全局默认楷体
String? contentFontFamily(String content) {
  if (_hasCjk(content)) return null; // 含中文：楷体
  if (_hasLatinLetter(content)) return 'EasyCreateBrand'; // 纯西文：品牌斜体
  return null; // 纯数字/符号/空：楷体
}

/// 是否该用品牌斜体（供 fontStyle 联动）
bool contentUsesBrandFont(String content) =>
    contentFontFamily(content) == 'EasyCreateBrand';

/// 品牌斜体的默认字距：衬线斜体本身较舒展，只补一点点
const double _brandTracking = 0.4;

/// 楷体的默认字距：汉字加一点间距更透气（方案 A 的关键观感之一）
const double _kaitiTracking = 1.0;

/// 按方案 A 产出内容文本样式：族/斜体/字距一次给齐，避免各处各写各的。
///
/// [letterSpacing] 省略时按语言取默认字距；标题类想更舒展可显式传更大值。
TextStyle contentTextStyle({
  required String text,
  required double fontSize,
  Color? color,
  FontWeight? fontWeight,
  double? height,
  double? letterSpacing,
  List<Shadow>? shadows,
}) {
  final brand = contentUsesBrandFont(text);
  return TextStyle(
    fontFamily: brand ? 'EasyCreateBrand' : 'LXGWWenKai',
    fontStyle: brand ? FontStyle.italic : FontStyle.normal,
    fontSize: fontSize,
    fontWeight: fontWeight ?? (brand ? FontWeight.w600 : FontWeight.w500),
    height: height,
    letterSpacing: letterSpacing ?? (brand ? _brandTracking : _kaitiTracking),
    color: color,
    shadows: shadows,
  );
}
