/// 灵感文本的字体选择：按内容语言统一到品牌视觉。
///
/// - 纯英文（含标点数字，但**不含中日韩汉字**）→ 品牌字体 EasyCreateBrand
///   斜体，与首页标题 "Create Something" 同款；
/// - 含中文 → 返回 null，落到全局默认楷体（LXGWWenKai）。
///
/// 判定用"是否出现 CJK 汉字"而非"是否含拉丁字母"，因为中英混排（如
/// "深夜的 metro"）应保持楷体正文体，只有整条是西文时才用品牌斜体。
library;

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

/// 是否至少含一个拉丁字母（纯符号/数字不算"英文灵感"）
bool _hasLatinLetter(String s) {
  for (final r in s.runes) {
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return true;
  }
  return false;
}

/// 灵感内容 → 字体族名；null 表示用全局默认楷体
String? inspirationFontFamily(String content) {
  if (_hasCjk(content)) return null; // 含中文：楷体
  if (_hasLatinLetter(content)) return 'EasyCreateBrand'; // 纯西文：品牌斜体
  return null; // 纯数字/符号/空：楷体
}

/// 是否应对该灵感用品牌斜体（供 fontStyle 联动）
bool inspirationIsBrand(String content) =>
    inspirationFontFamily(content) == 'EasyCreateBrand';
