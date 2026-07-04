import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/creative_energy.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import '../outline/outline_page.dart';
import 'orbiting_inspirations.dart';
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
  /// 当前浏览的星球下标（星空亮度跟随它对应的小说）
  int _currentPage = 0;

  /// 点击标题创建新星球：输入书名，纹理按现有数量轮换分配
  Future<void> _createNovel() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('创造一颗新星球'),
        content: TextField(
          key: const Key('新星球书名输入框'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '这部小说叫什么？'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('新星球确认按钮'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('诞生'),
          ),
        ],
      ),
    );

    final name = title?.trim() ?? '';
    if (name.isEmpty) return;
    final count = ref.read(novelsProvider).value?.length ?? 0;
    await ref
        .read(novelRepositoryProvider)
        .createNovel(
          title: name,
          planet: kPlanetTextures[count % kPlanetTextures.length],
        );
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
              itemCount: novels.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, i) =>
                  _PlanetPage(novel: novels[i], pool: pool),
            ),
          // 顶部标题：点击创建新星球
          // 定稿要求 Arabic Typesetting（微软授权字体，无法打包分发）——
          // 暂以衬线斜体近似，待终审；有授权字体文件放 assets/fonts 即可替换
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                key: const Key('创建新星球标题'),
                onTap: _createNovel,
                child: const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Text(
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
}

/// 单颗星球页：星球 + 环绕灵感 + 书名，点星球进大纲页
class _PlanetPage extends ConsumerWidget {
  const _PlanetPage({required this.novel, required this.pool});

  final Novel novel;
  final List<Inspiration> pool;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(creativeCountProvider(novel.id)).value ?? 0;
    final assets = ref.watch(planetAssetsProvider(novel.planet)).value;
    final diameter = MediaQuery.sizeOf(context).width * 0.62;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (assets != null)
          GestureDetector(
            key: Key('星球_${novel.id}'),
            // 点星球 → 进入该小说的大纲页（铅笔树）
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    OutlinePage(novelId: novel.id, title: novel.title),
              ),
            ),
            child: OrbitingInspirations(
              items: pool,
              orbitWidth: diameter * 1.5,
              // 土星带静态光环贴层，其余星球为纯球体
              child: novel.planet == 'saturn'
                  ? SaturnView(
                      assets: assets,
                      spin: planetSpin(count),
                      diameter: diameter,
                    )
                  : PlanetView(
                      assets: assets,
                      spin: planetSpin(count),
                      diameter: diameter,
                    ),
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

  /// 单击书名 → 重命名对话框 → 落库
  Future<void> _renameNovel(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: novel.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名这颗星球'),
        content: TextField(
          key: const Key('书名重命名输入框'),
          controller: controller,
          autofocus: true,
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('书名重命名确认按钮'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final title = newTitle?.trim() ?? '';
    if (title.isEmpty || title == novel.title) return;
    await ref.read(novelRepositoryProvider).renameNovel(novel.id, title);
  }
}
