import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// 灵感仓库：实现灵感生命周期四步流转（用户定稿规则）
///
/// ```
/// 新灵感 → 入池（section_id = NULL，排到魔毯末尾）
/// 拖入某小节 → section_id = 节 id（从魔毯消失）
/// 从小节删卡 → section_id 置回 NULL（放回魔毯末尾）
/// 在魔毯删除 → DELETE，真正删除不可恢复
/// ```
class InspirationRepository {
  InspirationRepository(this._db);

  final AppDatabase _db;

  /// 魔毯池末尾的下一个 card_order（池内最大值 +1，空池取 0）
  Future<int> _nextPoolOrder() async {
    final q = _db.selectOnly(_db.inspirations)
      ..addColumns([_db.inspirations.cardOrder.max()])
      ..where(
        _db.inspirations.sectionId.isNull() &
            _db.inspirations.chapterId.isNull(),
      );
    final max = (await q.getSingle()).read(_db.inspirations.cardOrder.max());
    return (max ?? -1) + 1;
  }

  /// 速记新灵感 → 入池（魔毯），排到末尾
  ///
  /// [createdAt] 仅测试注入用，正常调用不传、取当前时间。
  Future<Inspiration> addInspiration(String content, {DateTime? createdAt}) {
    final now = createdAt ?? DateTime.now();
    return _db.transaction(() async {
      final order = await _nextPoolOrder();
      return _db
          .into(_db.inspirations)
          .insertReturning(
            InspirationsCompanion.insert(
              content: content,
              createdAt: now,
              updatedAt: now,
              cardOrder: order,
            ),
          );
    });
  }

  /// 监听魔毯灵感池（section_id 为 NULL 的灵感）
  ///
  /// 排序（用户定稿 2026-07-08）：最早的灵感在最上（灵感一在顶），
  /// 主排序键 card_order 支持魔毯内手动重排，创建时间兜底。
  Stream<List<Inspiration>> watchPool() =>
      (_db.select(_db.inspirations)
            ..where((t) => t.sectionId.isNull() & t.chapterId.isNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.cardOrder),
              (t) => OrderingTerm.asc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .watch();

  /// 监听某小节的卡堆（按 card_order 升序，最新卡在 card_order 最大处）
  Stream<List<Inspiration>> watchSectionCards(int sectionId) =>
      (_db.select(_db.inspirations)
            ..where((t) => t.sectionId.equals(sectionId))
            ..orderBy([(t) => OrderingTerm.asc(t.cardOrder)]))
          .watch();

  /// 拖入小节：灵感从魔毯消失，归属该节，**排在卡堆最前**（成为当前展示卡，
  /// 用户定稿：卡包第一张 = 主区显示；刚拖入的应立即成为当前）
  Future<void> assignToSection(int inspirationId, int sectionId) async {
    final minOrderQuery = _db.selectOnly(_db.inspirations)
      ..addColumns([_db.inspirations.cardOrder.min()])
      ..where(_db.inspirations.sectionId.equals(sectionId));
    final row = await minOrderQuery.getSingle();
    final minOrder = row.read(_db.inspirations.cardOrder.min());
    // 空节首卡取 0；否则比现有最小再小 1（升序时排最前 = 当前展示）
    final newOrder = minOrder == null ? 0 : minOrder - 1;

    await (_db.update(
      _db.inspirations,
    )..where((t) => t.id.equals(inspirationId))).write(
      InspirationsCompanion(
        sectionId: Value(sectionId),
        chapterId: const Value(null), // 挂到小节即脱离"直接挂章"
        cardOrder: Value(newOrder),
      ),
    );
  }

  /// 拖到某章下：灵感直接挂在章（不属于任何小节），从魔毯消失
  Future<void> assignToChapter(int inspirationId, int chapterId) async {
    final maxOrderQuery = _db.selectOnly(_db.inspirations)
      ..addColumns([_db.inspirations.cardOrder.max()])
      ..where(_db.inspirations.chapterId.equals(chapterId));
    final row = await maxOrderQuery.getSingle();
    final maxOrder = row.read(_db.inspirations.cardOrder.max()) ?? -1;

    await (_db.update(
      _db.inspirations,
    )..where((t) => t.id.equals(inspirationId))).write(
      InspirationsCompanion(
        chapterId: Value(chapterId),
        sectionId: const Value(null),
        cardOrder: Value(maxOrder + 1),
      ),
    );
  }

  /// 从小节/章删卡：放回魔毯，排到末尾
  /// （魔毯支持手动排序后不再"回创建位"，末尾位置最可预期）
  Future<void> removeFromSection(int inspirationId) {
    return _db.transaction(() async {
      final order = await _nextPoolOrder();
      await (_db.update(
        _db.inspirations,
      )..where((t) => t.id.equals(inspirationId))).write(
        InspirationsCompanion(
          sectionId: const Value(null),
          chapterId: const Value(null),
          cardOrder: Value(order),
        ),
      );
    });
  }

  /// 在魔毯删除：真正删除，不可恢复（仅允许对魔毯中的灵感调用）
  Future<void> deleteForever(int inspirationId) => (_db.delete(
    _db.inspirations,
  )..where((t) => t.id.equals(inspirationId))).go();

  /// 卡堆重排序：按 [orderedIds] 的新顺序重写 card_order（0..n-1），
  /// 事务保证原子性（长按拖动重排的持久化）
  Future<void> reorderCards(List<int> orderedIds) {
    return _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.inspirations)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(InspirationsCompanion(cardOrder: Value(i)));
      }
    });
  }

  /// 编辑灵感正文（卡片全文编辑器保存时调用），刷新修改时间
  Future<void> updateContent(int inspirationId, String content) =>
      (_db.update(
        _db.inspirations,
      )..where((t) => t.id.equals(inspirationId))).write(
        InspirationsCompanion(
          content: Value(content),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
