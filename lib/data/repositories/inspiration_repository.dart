import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// 灵感仓库：实现灵感生命周期四步流转（用户定稿规则）
///
/// ```
/// 新灵感 → 入池（section_id = NULL，魔毯按创建时间排序）
/// 拖入某小节 → section_id = 节 id（从魔毯消失）
/// 从小节删卡 → section_id 置回 NULL（放回魔毯，仍按创建时间排序）
/// 在魔毯删除 → DELETE，真正删除不可恢复
/// ```
class InspirationRepository {
  InspirationRepository(this._db);

  final AppDatabase _db;

  /// 速记新灵感 → 入池（魔毯）
  ///
  /// [createdAt] 仅测试注入用，正常调用不传、取当前时间。
  Future<Inspiration> addInspiration(String content, {DateTime? createdAt}) {
    final now = createdAt ?? DateTime.now();
    return _db
        .into(_db.inspirations)
        .insertReturning(InspirationsCompanion.insert(
          content: content,
          createdAt: now,
          updatedAt: now,
          cardOrder: 0, // 在魔毯中无卡堆顺序，约定为 0
        ));
  }

  /// 监听魔毯灵感池（section_id 为 NULL 的灵感）
  ///
  /// 排序假设：定稿只说"按创建时间排序"，这里取新的在前，
  /// 保证速记后立刻出现在魔毯顶部、首页环绕取"最近几条"。
  Stream<List<Inspiration>> watchPool() => (_db.select(_db.inspirations)
        ..where((t) => t.sectionId.isNull())
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  /// 监听某小节的卡堆（按 card_order 升序，最新卡在 card_order 最大处）
  Stream<List<Inspiration>> watchSectionCards(int sectionId) =>
      (_db.select(_db.inspirations)
            ..where((t) => t.sectionId.equals(sectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.cardOrder)]))
          .watch();

  /// 拖入小节：灵感从魔毯消失，归属该节，排在卡堆末尾
  Future<void> assignToSection(int inspirationId, int sectionId) async {
    final maxOrderQuery = _db.selectOnly(_db.inspirations)
      ..addColumns([_db.inspirations.cardOrder.max()])
      ..where(_db.inspirations.sectionId.equals(sectionId));
    final row = await maxOrderQuery.getSingle();
    final maxOrder = row.read(_db.inspirations.cardOrder.max()) ?? -1;

    await (_db.update(_db.inspirations)
          ..where((t) => t.id.equals(inspirationId)))
        .write(InspirationsCompanion(
      sectionId: Value(sectionId),
      cardOrder: Value(maxOrder + 1),
    ));
  }

  /// 从小节删卡：放回魔毯（创建时间不变，排序位置由它决定）
  Future<void> removeFromSection(int inspirationId) =>
      (_db.update(_db.inspirations)..where((t) => t.id.equals(inspirationId)))
          .write(const InspirationsCompanion(
        sectionId: Value(null),
        cardOrder: Value(0),
      ));

  /// 在魔毯删除：真正删除，不可恢复（仅允许对魔毯中的灵感调用）
  Future<void> deleteForever(int inspirationId) =>
      (_db.delete(_db.inspirations)..where((t) => t.id.equals(inspirationId)))
          .go();

  /// 编辑灵感正文（卡片全文编辑器保存时调用），刷新修改时间
  Future<void> updateContent(int inspirationId, String content) =>
      (_db.update(_db.inspirations)..where((t) => t.id.equals(inspirationId)))
          .write(InspirationsCompanion(
        content: Value(content),
        updatedAt: Value(DateTime.now()),
      ));
}
