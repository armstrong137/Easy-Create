/// 三维场景投影到 Flutter 交互层的章节或小节标签。
class PlacedLabel {
  const PlacedLabel({required this.text, this.chapterId, this.sectionId});

  final String text;
  final int? chapterId;
  final int? sectionId;
}
