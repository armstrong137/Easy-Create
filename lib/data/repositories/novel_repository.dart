import 'package:drift/drift.dart';

import '../../domain/entities/outline_chapter.dart';
import '../database/app_database.dart';

/// 大纲结构仓库：小说（星球）→ 章 → 节 三层的增删改查
///
/// 删除均依赖数据库级联规则：删小说→删章→删节；
/// 删节时其下灵感由外键置回魔毯（见 tables.dart 的 Inspirations 注释）。
class NovelRepository {
  NovelRepository(this._db);

  final AppDatabase _db;

  // ---------- 小说（星球） ----------

  /// 按首页排列顺序监听全部小说（星球 PageView 数据源）
  Stream<List<Novel>> watchNovels() =>
      (_db.select(_db.novels)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  /// 创建小说：排在现有星球末尾
  Future<Novel> createNovel({
    required String title,
    required String planet,
  }) async {
    final maxOrder = await _maxSortOrder(_db.novels, _db.novels.sortOrder);
    return _db.into(_db.novels).insertReturning(NovelsCompanion.insert(
          title: title,
          planet: planet,
          sortOrder: maxOrder + 1,
          createdAt: DateTime.now(),
        ));
  }

  /// 重命名小说
  Future<void> renameNovel(int id, String title) =>
      (_db.update(_db.novels)..where((t) => t.id.equals(id)))
          .write(NovelsCompanion(title: Value(title)));

  /// 删除小说（级联删除其下章与节；节下灵感放回魔毯）
  Future<void> deleteNovel(int id) =>
      (_db.delete(_db.novels)..where((t) => t.id.equals(id))).go();

  // ---------- 章 ----------

  /// 按树上顺序监听某小说的全部章
  Stream<List<Chapter>> watchChapters(int novelId) => (_db.select(_db.chapters)
        ..where((t) => t.novelId.equals(novelId))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
      .watch();

  /// 新增章：长在该小说现有章之后
  Future<Chapter> createChapter({
    required int novelId,
    required String title,
  }) async {
    final maxOrder = await _maxSortOrder(
      _db.chapters,
      _db.chapters.sortOrder,
      where: _db.chapters.novelId.equals(novelId),
    );
    return _db.into(_db.chapters).insertReturning(ChaptersCompanion.insert(
          novelId: novelId,
          title: title,
          sortOrder: maxOrder + 1,
        ));
  }

  /// 重命名章
  Future<void> renameChapter(int id, String title) =>
      (_db.update(_db.chapters)..where((t) => t.id.equals(id)))
          .write(ChaptersCompanion(title: Value(title)));

  /// 删除章（级联删除其下节；节下灵感放回魔毯）
  Future<void> deleteChapter(int id) =>
      (_db.delete(_db.chapters)..where((t) => t.id.equals(id))).go();

  // ---------- 节 ----------

  /// 按章内顺序监听某章的全部节
  Stream<List<Section>> watchSections(int chapterId) =>
      (_db.select(_db.sections)
            ..where((t) => t.chapterId.equals(chapterId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  /// 新增节：长在该章现有节之后
  Future<Section> createSection({
    required int chapterId,
    required String title,
  }) async {
    final maxOrder = await _maxSortOrder(
      _db.sections,
      _db.sections.sortOrder,
      where: _db.sections.chapterId.equals(chapterId),
    );
    return _db.into(_db.sections).insertReturning(SectionsCompanion.insert(
          chapterId: chapterId,
          title: title,
          sortOrder: maxOrder + 1,
        ));
  }

  /// 重命名节（小节页顶部可编辑标题）
  Future<void> renameSection(int id, String title) =>
      (_db.update(_db.sections)..where((t) => t.id.equals(id)))
          .write(SectionsCompanion(title: Value(title)));

  /// 删除节（其下灵感由外键置回魔毯，不陪葬）
  Future<void> deleteSection(int id) =>
      (_db.delete(_db.sections)..where((t) => t.id.equals(id))).go();

  // ---------- 大纲树 ----------

  /// 监听某小说的完整大纲（章 + 各章的节，均按 sort_order），铅笔树数据源
  Stream<List<OutlineChapter>> watchOutline(int novelId) {
    final query = _db.select(_db.chapters).join([
      leftOuterJoin(
          _db.sections, _db.sections.chapterId.equalsExp(_db.chapters.id)),
    ])
      ..where(_db.chapters.novelId.equals(novelId))
      ..orderBy([
        OrderingTerm.asc(_db.chapters.sortOrder),
        OrderingTerm.asc(_db.sections.sortOrder),
      ]);

    return query.watch().map((rows) {
      // 按章分组（保持章的排序），聚合各章的节
      final grouped = <int, (Chapter, List<Section>)>{};
      for (final row in rows) {
        final chapter = row.readTable(_db.chapters);
        final section = row.readTableOrNull(_db.sections);
        final entry =
            grouped.putIfAbsent(chapter.id, () => (chapter, <Section>[]));
        if (section != null) entry.$2.add(section);
      }
      return [
        for (final (chapter, sections) in grouped.values)
          OutlineChapter(chapter: chapter, sections: sections),
      ];
    });
  }

  // ---------- 创作能量 ----------

  /// 监听某小说的创作量 = 章数 + 节数 + 挂在其小节下的灵感数
  /// （首页星球转速与星空亮度的数据源；魔毯中未归属的灵感不计入）
  Stream<int> watchCreativeCount(int novelId) {
    final query = _db.customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM chapters WHERE novel_id = ?1)
        + (SELECT COUNT(*) FROM sections s
             JOIN chapters c ON s.chapter_id = c.id
             WHERE c.novel_id = ?1)
        + (SELECT COUNT(*) FROM inspirations i
             JOIN sections s ON i.section_id = s.id
             JOIN chapters c ON s.chapter_id = c.id
             WHERE c.novel_id = ?1) AS total
      ''',
      variables: [Variable.withInt(novelId)],
      readsFrom: {_db.chapters, _db.sections, _db.inspirations},
    );
    return query.watchSingle().map((row) => row.read<int>('total'));
  }

  // ---------- 内部工具 ----------

  /// 查某表（可加条件）当前最大 sort_order，空表返回 -1
  Future<int> _maxSortOrder<T extends Table, R>(
    TableInfo<T, R> table,
    GeneratedColumn<int> column, {
    Expression<bool>? where,
  }) async {
    final query = _db.selectOnly(table)..addColumns([column.max()]);
    if (where != null) query.where(where);
    final row = await query.getSingle();
    return row.read(column.max()) ?? -1;
  }
}
