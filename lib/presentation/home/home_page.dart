import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/creative_energy.dart';
import '../../data/database/app_database.dart';
import '../../data/providers.dart';
import 'starfield.dart';

/// 魔毯灵感池流（首页星空亮度暂由它驱动）
final inspirationPoolProvider = StreamProvider<List<Inspiration>>(
  (ref) => ref.watch(inspirationRepositoryProvider).watchPool(),
);

/// 首页｜创作宇宙
///
/// 当前形态（阶段三·1）：程序化星空 + 占位标题。
/// 亮度暂按魔毯灵感数计算（过渡态）；阶段三·5 多星球后
/// 改为"当前小说的灵感数+章节数"。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poolCount = ref.watch(inspirationPoolProvider).value?.length ?? 0;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Starfield(brightness: starBrightness(poolCount)),
          // 顶部标题：阶段三·5 换 Arabic Typesetting 字体并接"创建新星球"
          const SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  'Create Something',
                  style: TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
