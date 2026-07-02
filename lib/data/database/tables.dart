import 'package:drift/drift.dart';

// ==============================================================
// 数据表定义（与 docs/superpowers/specs/2026-07-02-novel-app-design.md 第五节一致）
// 4 张表：novels / chapters / sections / inspirations
// ==============================================================

/// 小说表（首页一颗星球 = 一部小说）
class Novels extends Table {
  /// 主键，自增
  IntColumn get id => integer().autoIncrement()();

  /// 小说标题
  TextColumn get title => text()();

  /// 星球贴图标识（earth / mars / jupiter / mercury …）
  TextColumn get planet => text()();

  /// 首页星球排列顺序
  IntColumn get sortOrder => integer().named('sort_order')();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime().named('created_at')();
}

/// 章表（大纲树的章级枝丫）
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属小说，级联删除：删星球时章一并删除
  IntColumn get novelId => integer()
      .named('novel_id')
      .references(Novels, #id, onDelete: KeyAction.cascade)();

  /// 章标题（引子 / 第一章 …）
  TextColumn get title => text()();

  /// 树上章级枝丫顺序
  IntColumn get sortOrder => integer().named('sort_order')();
}

/// 节表（大纲树的节级枝丫）
class Sections extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 所属章，级联删除
  IntColumn get chapterId => integer()
      .named('chapter_id')
      .references(Chapters, #id, onDelete: KeyAction.cascade)();

  /// 节标题（第一节 / 第二节 …）
  TextColumn get title => text()();

  /// 章内节顺序
  IntColumn get sortOrder => integer().named('sort_order')();
}

/// 灵感表（灵感真身，生命周期由 sectionId 单字段表达）
///
/// 生命周期规则（用户定稿）：
/// - 新灵感入池：sectionId = NULL（在魔毯，所有星球共享，按创建时间排序）
/// - 拖入某小节：sectionId = 该节 id（从魔毯消失，魔毯缩球）
/// - 从小节删卡：sectionId 置回 NULL（放回魔毯，仍按创建时间排序）
/// - 在魔毯删除：DELETE 行，真正删除不可恢复
class Inspirations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 灵感正文，无字数上限（可写完整小说）
  TextColumn get content => text()();

  /// 创建时间（魔毯排序依据，放回后仍按它排序）
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  /// 最后修改时间
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  /// 归属小节：NULL = 在魔毯；非空 = 挂在该小节。
  /// 删除小节时置空（灵感放回魔毯，不随节陪葬）
  IntColumn get sectionId => integer()
      .named('section_id')
      .nullable()
      .references(Sections, #id, onDelete: KeyAction.setNull)();

  /// 小节内卡堆顺序（在魔毯时无意义，约定为 0）
  IntColumn get cardOrder => integer().named('card_order')();
}
