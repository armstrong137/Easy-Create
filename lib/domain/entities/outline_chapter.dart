import '../../data/database/app_database.dart';

/// 大纲树的一根章枝：章 + 其下全部节（按 sort_order 排好）
class OutlineChapter {
  const OutlineChapter({required this.chapter, required this.sections});

  final Chapter chapter;
  final List<Section> sections;
}
