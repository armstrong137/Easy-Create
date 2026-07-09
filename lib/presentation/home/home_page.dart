import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/creative_energy.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../outline/outline_page.dart';
import '../settings/settings_page.dart';
import 'orbiting_inspirations.dart';
import 'planet_scene/planet_scene.dart';
import 'planet_view.dart';
import 'saturn_rings_painter.dart';
import 'starfield.dart';

/// 魔毯灵感池流（全局共享，环绕文字数据源）
final inspirationPoolProvider = StreamProvider<List<Inspiration>>(
  (ref) => ref.watch(inspirationRepositoryProvider).watchPool(),
);

/// 全部小说（星球），按首页排列顺序
final novelsProvider = StreamProvider<List<Novel>>(
  (ref) => ref.watch(novelRepositoryProvider).watchNovels(),
);

/// 某小说的创作量（章+节+其下灵感），驱动该星球转速与星空亮度
final creativeCountProvider = StreamProvider.family<int, int>(
  (ref, novelId) =>
      ref.watch(novelRepositoryProvider).watchCreativeCount(novelId),
);

/// 星球 shader 资源（按行星纹理名缓存，如 'earth'）
final planetAssetsProvider = FutureProvider.family<PlanetShaderAssets, String>(
  (ref, planet) => PlanetShaderAssets.load(planet),
);

/// 可选行星纹理（新建星球按当前数量轮换分配）
const kPlanetTextures = ['earth', 'mars', 'jupiter', 'venus', 'saturn'];

/// 首页｜创作宇宙：一颗星球 = 一部小说，左右滑切换
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  late final PageController _pageController;

  /// 当前浏览的星球下标（星空亮度跟随它对应的小说）
  int _currentPage = 0;

  int? _pendingNovelId;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// 点击标题创建新星球：输入书名，纹理按现有数量轮换分配
  Future<void> _createNovel() async {
    final title = await _promptText(
      context: context,
      heading: '创造一颗新星球',
      hint: '这部小说叫什么？',
      confirm: '诞生',
      fieldKey: const Key('新星球书名输入框'),
      confirmKey: const Key('新星球确认按钮'),
    );

    final name = title?.trim() ?? '';
    if (name.isEmpty) return;
    final count = ref.read(novelsProvider).value?.length ?? 0;
    final novel = await ref
        .read(novelRepositoryProvider)
        .createNovel(
          title: name,
          planet: kPlanetTextures[count % kPlanetTextures.length],
        );
    if (!mounted) return;
    setState(() => _pendingNovelId = novel.id);
    _scheduleCreatedNovelJump(ref.read(novelsProvider).value ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final novels = ref.watch(novelsProvider).value ?? const [];
    final pool = ref.watch(inspirationPoolProvider).value ?? const [];

    // 当前星球的创作量 → 星空亮度（无星球时最暗）
    final currentNovel = novels.isEmpty
        ? null
        : novels[_currentPage.clamp(0, novels.length - 1)];
    final currentCount = currentNovel == null
        ? 0
        : ref.watch(creativeCountProvider(currentNovel.id)).value ?? 0;
    _scheduleCreatedNovelJump(novels);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Starfield(brightness: starBrightness(currentCount)),
          if (novels.isEmpty)
            // 空宇宙：邀请创建第一颗星球
            const Center(
              child: Text(
                '宇宙一片寂静\n点上方 Create Something 点亮第一颗星球',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            )
          else
            // 一页一星球，左右滑切换小说
            PageView.builder(
              controller: _pageController,
              itemCount: novels.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, i) =>
                  _PlanetPage(novel: novels[i], pool: pool),
            ),
          // 左上角设置入口（齿轮）：进设置页改速记按钮左右侧
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: GestureDetector(
                  key: const Key('设置入口'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      CupertinoIcons.gear,
                      color: Colors.white70,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 顶部标题：点击创建新星球
          // 定稿要求 Arabic Typesetting（微软授权字体，无法打包分发）——
          // 暂以衬线斜体近似，待终审；有授权字体文件放 assets/fonts 即可替换
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              // 下移到右上角魔毯球（92px）下方，避免标题右端与球重叠。
              // padding 放在 GestureDetector 外，热区只裹文字（点击命中稳定）
              child: Padding(
                padding: const EdgeInsets.only(top: 100),
                child: GestureDetector(
                  key: const Key('创建新星球标题'),
                  onTap: _createNovel,
                  child: const Text(
                    'Create Something',
                    style: TextStyle(
                      fontSize: 26,
                      color: Colors.white,
                      fontFamily: 'serif',
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleCreatedNovelJump(List<Novel> novels) {
    final pendingId = _pendingNovelId;
    if (pendingId == null) return;
    final target = novels.indexWhere((n) => n.id == pendingId);
    if (target < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pendingNovelId != pendingId) return;
      _pendingNovelId = null;
      setState(() => _currentPage = target);
      if (!_pageController.hasClients) return;
      _pageController.jumpToPage(target);
    });
  }
}

/// 单颗星球页：星球 + 环绕灵感 + 书名，点星球进大纲页
class _PlanetPage extends ConsumerWidget {
  const _PlanetPage({required this.novel, required this.pool});

  final Novel novel;
  final List<Inspiration> pool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(creativeCountProvider(novel.id)).value ?? 0;
    final use3D = ref.watch(advanced3DProvider);
    // 3D 场景不依赖 shader 资源；旧路径（测试/低端回退）仍需等待加载
    final assets = use3D
        ? null
        : ref.watch(planetAssetsProvider(novel.planet)).value;
    final diameter = MediaQuery.sizeOf(context).width * 0.62;
    final ready = use3D || assets != null;

    // 星球本体：真实 3D 场景（阶段八 P2-1）或旧 FragmentShader（回退）
    Widget planetBody() {
      if (use3D) {
        return PlanetScene(
          planet: novel.planet,
          spin: planetSpin(count),
          // 土星的 3D 环带在场景内渲染，加宽画幅给环留位
          diameter: novel.planet == 'saturn' ? diameter * 1.4 : diameter,
        );
      }
      return novel.planet == 'saturn'
          ? SaturnView(
              assets: assets!,
              spin: planetSpin(count),
              diameter: diameter,
            )
          : PlanetView(
              assets: assets!,
              spin: planetSpin(count),
              diameter: diameter,
            );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          key: Key('星球_${novel.id}'),
          behavior: HitTestBehavior.opaque,
          // 点星球 → 进入该小说的大纲页（铅笔树）
          onTap: !ready
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        OutlinePage(novelId: novel.id, title: novel.title),
                  ),
                ),
          onLongPress: () => _confirmDeleteNovel(context, ref),
          child: !ready
              ? SizedBox.square(dimension: diameter)
              : OrbitingInspirations(
                  // 环绕取"最近几条"：魔毯池已改为旧→新/手动序，
                  // 这里单独按创建时间倒序取最新（轨道显示灵感原文）
                  items: [...pool]
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
                  orbitWidth: diameter * 1.5,
                  child: planetBody(),
                ),
        ),
        const SizedBox(height: 28),
        // 书名（楷体白字）：单击可重命名（2026-07-03 用户需求）
        GestureDetector(
          key: Key('书名_${novel.id}'),
          onTap: () => _renameNovel(context, ref),
          child: Text(
            novel.title,
            style: const TextStyle(
              fontFamily: 'LXGWWenKai',
              fontSize: 18,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteNovel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text('删除这颗星球？', style: _dlgStyle(weight: FontWeight.w600)),
        content: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            '「${novel.title}」的大纲会被剪掉，挂在小节里的灵感会回到魔毯。',
            style: _dlgStyle(size: 14, color: const Color(0xFF4A3A28)),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('取消', style: _dlgStyle()),
          ),
          CupertinoDialogAction(
            key: const Key('星球删除确认按钮'),
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('删除', style: _dlgStyle(weight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(novelRepositoryProvider).deleteNovel(novel.id);
    }
  }

  /// 单击书名 → 重命名对话框 → 落库
  Future<void> _renameNovel(BuildContext context, WidgetRef ref) async {
    final newTitle = await _promptText(
      context: context,
      heading: '重命名这颗星球',
      hint: '新名字',
      confirm: '保存',
      initial: novel.title,
      fieldKey: const Key('书名重命名输入框'),
      confirmKey: const Key('书名重命名确认按钮'),
    );
    final title = newTitle?.trim() ?? '';
    if (title.isEmpty || title == novel.title) return;
    await ref.read(novelRepositoryProvider).renameNovel(novel.id, title);
  }
}

/// 楷体文字（弹窗共用）
TextStyle _dlgStyle({double size = 17, FontWeight? weight, Color? color}) =>
    TextStyle(
      fontFamily: 'LXGWWenKai',
      fontSize: size,
      fontWeight: weight,
      color: color,
    );

/// iOS 质感文字输入弹窗（建星球/重命名共用，替代 Material AlertDialog）
Future<String?> _promptText({
  required BuildContext context,
  required String heading,
  required String hint,
  required String confirm,
  required Key fieldKey,
  required Key confirmKey,
  String? initial,
}) {
  final controller = TextEditingController(text: initial);
  final result = showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final media = MediaQuery.of(dialogContext);
      final width = math.min(media.size.width - 48, 330.0);
      return Material(
        type: MaterialType.transparency,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 34),
                child: Container(
                  key: const Key('星球名称弹窗卡片'),
                  width: width,
                  decoration: BoxDecoration(
                    color: const Color(0xF8FFFDF8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                        child: Text(
                          heading,
                          textAlign: TextAlign.center,
                          style: _dlgStyle(
                            size: 20,
                            weight: FontWeight.w600,
                            color: const Color(0xFF3D332A),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: CupertinoTextField(
                          key: fieldKey,
                          controller: controller,
                          autofocus: true,
                          placeholder: hint,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE3D8C7)),
                          ),
                          style: _dlgStyle(
                            size: 16,
                            color: const Color(0xFF1A1A1A),
                          ),
                          placeholderStyle: _dlgStyle(
                            size: 16,
                            color: const Color(0x993D332A),
                          ),
                          onSubmitted: (v) =>
                              Navigator.of(dialogContext).pop(v),
                        ),
                      ),
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0x1F3D332A)),
                          ),
                        ),
                        child: SizedBox(
                          height: 54,
                          child: Row(
                            children: [
                              Expanded(
                                child: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: Text(
                                    '取消',
                                    style: _dlgStyle(
                                      size: 18,
                                      color: const Color(0xFF8C4A63),
                                    ),
                                  ),
                                ),
                              ),
                              const VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: Color(0x1F3D332A),
                              ),
                              Expanded(
                                child: CupertinoButton(
                                  key: confirmKey,
                                  padding: EdgeInsets.zero,
                                  onPressed: () => Navigator.of(
                                    dialogContext,
                                  ).pop(controller.text),
                                  child: Text(
                                    confirm,
                                    style: _dlgStyle(
                                      size: 18,
                                      weight: FontWeight.w600,
                                      color: const Color(0xFF8C4A63),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  return result.whenComplete(controller.dispose);
}
