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

/// 灵感表（灵感真身）
///
/// 生命周期规则（用户定稿，2026-07-03 扩展"可挂靠章"）：
/// - 新灵感入池：section_id 与 chapter_id 均 NULL（在魔毯，所有星球共享）
/// - 拖入某小节：section_id = 该节 id（chapter_id 清空，从魔毯消失）
/// - 拖到某章下：chapter_id = 该章 id（section_id 清空，从魔毯消失）
/// - 放回魔毯：两字段都置 NULL（仍按创建时间排序）
/// - 在魔毯删除：DELETE 行，真正删除不可恢复
/// 约束：section_id 与 chapter_id 至多一个非空。
class Inspirations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 灵感正文，无字数上限（可写完整小说）
  TextColumn get content => text()();

  /// 创建时间（魔毯排序依据，放回后仍按它排序）
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  /// 最后修改时间
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  /// 归属小节：NULL = 未挂在小节；非空 = 挂在该小节。
  /// 删除小节时置空（灵感放回魔毯，不随节陪葬）
  IntColumn get sectionId => integer()
      .named('section_id')
      .nullable()
      .references(Sections, #id, onDelete: KeyAction.setNull)();

  /// 归属章：NULL = 未直接挂在章；非空 = 直接挂在该章下（不属于任何小节）。
  /// 删除章时置空（灵感放回魔毯）
  IntColumn get chapterId => integer()
      .named('chapter_id')
      .nullable()
      .references(Chapters, #id, onDelete: KeyAction.setNull)();

  /// 小节内卡堆顺序（在魔毯时无意义，约定为 0）
  IntColumn get cardOrder => integer().named('card_order')();
}
