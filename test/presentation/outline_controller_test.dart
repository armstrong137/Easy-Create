import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/data/database/app_database.dart';
import 'package:novel_app/domain/entities/outline_chapter.dart';
import 'package:novel_app/presentation/outline/outline_controller.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_controller.dart';
import 'package:novel_app/presentation/outline/tree_scene/tree_scene_protocol.dart';

OutlineChapter chapter(int id, {int sections = 0}) => OutlineChapter(
  chapter: Chapter(id: id, novelId: 1, title: '第$id章', sortOrder: id),
  sections: [
    for (var index = 0; index < sections; index += 1)
      Section(
        id: id * 100 + index,
        chapterId: id,
        title: '第${index + 1}节',
        sortOrder: index,
      ),
  ],
);

void main() {
  late List<Map<String, Object?>> sent;
  late TreeSceneController scene;
  late OutlineController controller;

  setUp(() async {
    sent = [];
    scene = TreeSceneController(sessionId: 'outline-test')
      ..attachSender((command) async => sent.add(command));
    await scene.markReadyForTest();
    controller = OutlineController(
      novelId: 1,
      scene: scene,
      createChapter: () async =>
          const Chapter(id: 99, novelId: 1, title: '新章', sortOrder: 99),
      createSection: (chapterId) async =>
          Section(id: 9900, chapterId: chapterId, title: '新节', sortOrder: 0),
      renameChapter: (_, _) async {},
      renameSection: (_, _) async {},
      deleteChapter: (_) async {},
      deleteSection: (_) async {},
    );
  });

  tearDown(() {
    controller.dispose();
    scene.dispose();
  });

  test('首次进入只发完整快照并默认聚焦最新章', () {
    controller.onOutlineChanged([chapter(1), chapter(2)]);

    expect(sent, hasLength(1));
    expect(sent.single['type'], 'tree.syncSnapshot');
    final payload = sent.single['payload']! as Map<String, Object?>;
    expect(payload['focusedChapterId'], 2);
  });

  test('新增章和新增节各只发送一次主 mutation', () async {
    controller.onOutlineChanged([chapter(1)]);
    sent.clear();
    controller.onOutlineChanged([chapter(1), chapter(2)]);
    controller.onOutlineChanged([chapter(1), chapter(2)]);
    expect(sent, hasLength(1));
    expect(sent.single['type'], 'tree.playMutation');

    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 9,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );
    sent.clear();
    controller.onOutlineChanged([chapter(1), chapter(2, sections: 1)]);
    expect(sent, hasLength(1));
    final payload = sent.single['payload']! as Map<String, Object?>;
    final mutation = payload['mutation']! as Map<String, Object?>;
    expect(mutation['type'], 'addSection');
  });

  test('新建章节仅在数据库流确认返回 ID 后聚焦该章节', () async {
    controller.onOutlineChanged([chapter(1), chapter(2), chapter(3)]);
    controller.focusChapter(1, animate: false);

    await controller.addChapter();
    expect(controller.snapshot?.focusedChapterId, 1);

    final created = OutlineChapter(
      chapter: const Chapter(id: 99, novelId: 1, title: '新章', sortOrder: 1),
      sections: const [],
    );
    controller.onOutlineChanged([chapter(1), created, chapter(2), chapter(3)]);

    expect(controller.snapshot?.focusedChapterId, 99);
  });

  test('新建节点已随 mutation 同步焦点时不重复发送 focus', () async {
    controller.onOutlineChanged([chapter(1)]);
    sent.clear();

    await controller.addChapter();
    controller.onOutlineChanged([chapter(1), chapter(99)]);
    expect(sent.map((command) => command['type']), ['tree.playMutation']);

    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 11,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );
    expect(sent.map((command) => command['type']), ['tree.playMutation']);
  });

  test('生长期间的手动导航会取消创建后的延迟场景聚焦', () async {
    final delayed = Completer<Chapter>();
    controller.dispose();
    controller = OutlineController(
      novelId: 1,
      scene: scene,
      createChapter: () => delayed.future,
      createSection: (chapterId) async =>
          Section(id: 9900, chapterId: chapterId, title: '新节', sortOrder: 0),
      renameChapter: (_, _) async {},
      renameSection: (_, _) async {},
      deleteChapter: (_) async {},
      deleteSection: (_) async {},
    );
    controller.onOutlineChanged([chapter(1), chapter(2)]);
    controller.focusChapter(1, animate: false);
    sent.clear();

    final creation = controller.addChapter();
    controller.onOutlineChanged([chapter(1), chapter(2), chapter(99)]);
    delayed.complete(
      const Chapter(id: 99, novelId: 1, title: '新章', sortOrder: 99),
    );
    await creation;
    controller.focusChapter(2);

    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 12,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );

    expect(controller.focusedChapterId, 2);
    final focusCommands = sent
        .where((command) => command['type'] == 'tree.focusChapter')
        .toList();
    expect(focusCommands, hasLength(2));
    expect((focusCommands.last['payload']! as Map<String, Object?>)['id'], 2);
  });

  test('创建 Future 返回前的手动导航会取消自动聚焦且保持内部焦点一致', () async {
    final delayed = Completer<Chapter>();
    controller.dispose();
    controller = OutlineController(
      novelId: 1,
      scene: scene,
      createChapter: () => delayed.future,
      createSection: (chapterId) async =>
          Section(id: 9900, chapterId: chapterId, title: '新节', sortOrder: 0),
      renameChapter: (_, _) async {},
      renameSection: (_, _) async {},
      deleteChapter: (_) async {},
      deleteSection: (_) async {},
    );
    controller.onOutlineChanged([chapter(1), chapter(2)]);
    controller.focusChapter(1, animate: false);
    sent.clear();

    final creation = controller.addChapter();
    controller.onOutlineChanged([chapter(1), chapter(2), chapter(99)]);
    controller.focusChapter(2);
    delayed.complete(
      const Chapter(id: 99, novelId: 1, title: '新章', sortOrder: 99),
    );
    await creation;
    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 15,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );

    expect(controller.focusedChapterId, 2);
    expect(controller.snapshot?.focusedChapterId, 2);
    final focusCommands = sent
        .where((command) => command['type'] == 'tree.focusChapter')
        .toList();
    expect(focusCommands, hasLength(2));
    expect((focusCommands.last['payload']! as Map<String, Object?>)['id'], 2);
  });

  test('创建 Future 返回后到 stream 确认前点击当前章会取消小节自动聚焦', () async {
    controller.onOutlineChanged([chapter(1)]);
    sent.clear();

    await controller.addSection(1);
    controller.focusChapter(1);
    final withSection = OutlineChapter(
      chapter: chapter(1).chapter,
      sections: const [
        Section(id: 9900, chapterId: 1, title: '新节', sortOrder: 0),
      ],
    );
    controller.onOutlineChanged([withSection]);
    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 16,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );

    expect(controller.focusedChapterId, 1);
    expect(controller.focusedSectionId(1), isNull);
    expect(
      sent.where((command) => command['type'] == 'tree.focusSection'),
      isEmpty,
    );
  });

  test('新建小节会在生长完成后聚焦该小节', () async {
    controller.onOutlineChanged([chapter(1)]);
    sent.clear();

    await controller.addSection(1);
    final withSection = OutlineChapter(
      chapter: chapter(1).chapter,
      sections: const [
        Section(id: 9900, chapterId: 1, title: '新节', sortOrder: 0),
      ],
    );
    controller.onOutlineChanged([withSection]);
    expect(sent.map((command) => command['type']), ['tree.playMutation']);

    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 13,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );

    expect(sent.map((command) => command['type']), [
      'tree.playMutation',
      'tree.focusSection',
    ]);
  });

  test('点击当前章会取消新建小节的自动聚焦并在生长后重放章节焦点', () async {
    controller.onOutlineChanged([chapter(1)]);
    sent.clear();

    await controller.addSection(1);
    final withSection = OutlineChapter(
      chapter: chapter(1).chapter,
      sections: const [
        Section(id: 9900, chapterId: 1, title: '新节', sortOrder: 0),
      ],
    );
    controller.onOutlineChanged([withSection]);
    controller.focusChapter(1);

    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 14,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );

    expect(
      sent.where((command) => command['type'] == 'tree.focusSection'),
      isEmpty,
    );
    expect(
      sent.where((command) => command['type'] == 'tree.focusChapter'),
      hasLength(2),
    );
  });

  test('事务完成前后续结构只保留最新快照', () async {
    controller.onOutlineChanged([chapter(1)]);
    sent.clear();
    controller.onOutlineChanged([chapter(1), chapter(2)]);
    controller.onOutlineChanged([chapter(1), chapter(2), chapter(3)]);
    expect(sent, hasLength(1));

    await controller.onSceneEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 10,
        type: 'tree.mutationCompleted',
        payload: {},
      ),
    );
    expect(sent, hasLength(2));
  });

  test('静态回退不等待场景动画完成并持续同步最新树龄', () {
    controller.onOutlineChanged([chapter(1)], animateMutations: false);
    sent.clear();

    controller.onOutlineChanged([
      chapter(1),
      chapter(2),
    ], animateMutations: false);
    controller.onOutlineChanged([
      chapter(1),
      chapter(2),
      chapter(3),
    ], animateMutations: false);

    expect(sent, hasLength(2));
    expect(
      sent.every((command) => command['type'] == 'tree.syncSnapshot'),
      isTrue,
    );
    expect(controller.snapshot?.chapters, hasLength(3));
  });

  test('运行中降级会立即落地正在等待的最新快照', () async {
    controller.onOutlineChanged([chapter(1)]);
    sent.clear();
    controller.onOutlineChanged([chapter(1), chapter(2)]);
    controller.onOutlineChanged([chapter(1), chapter(2), chapter(3)]);
    expect(sent, hasLength(1));

    await scene.handleEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 11,
        type: 'scene.recoveryFailed',
        payload: {},
      ),
    );
    await scene.handleEvent(
      const TreeSceneEvent(
        sessionId: 'outline-test',
        sequence: 12,
        type: 'scene.recoveryFailed',
        payload: {},
      ),
    );

    expect(sent, hasLength(1));
    expect(controller.snapshot?.chapters, hasLength(3));
  });
}
