import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/carpet_constants.dart';
import '../../data/database/app_database.dart';
import '../home/home_page.dart' show inspirationPoolProvider;

/// 灵感魔毯：全局灵感容器，驻留大纲页右上角、永远最顶层
///
/// - 缩球态：阿拉丁配色的小球（径向渐变 + 金色织边）
/// - 点击展开：占屏幕上部一小部分，高度随灵感数伸缩（有上下限），
///   最多显示若干条、内部下滑加载更多，按创建时间新的在前
/// - 展开/收起为程序化补间动效（定稿允许 Rive 或程序化，选后者轻量）
class MagicCarpet extends ConsumerStatefulWidget {
  const MagicCarpet({super.key});

  @override
  ConsumerState<MagicCarpet> createState() => MagicCarpetState();
}

class MagicCarpetState extends ConsumerState<MagicCarpet> {
  bool _expanded = false;

  bool get expanded => _expanded;

  /// 外部可调用：拖拽完成后自动缩回小球（定稿）
  void collapse() {
    if (_expanded && mounted) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final pool = ref.watch(inspirationPoolProvider).value ?? const [];
    final width = MediaQuery.sizeOf(context).width * 0.86;

    final height = carpetHeight(pool.length);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      width: _expanded ? width : kCarpetBallSize,
      height: _expanded ? height : kCarpetBallSize,
      // 裁剪：展开动画中间帧内容按最终尺寸布局，超出部分剪掉
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // 缩球=圆形径向渐变；展开=圆角绒毯 + 金色织边
        shape: BoxShape.rectangle,
        borderRadius:
            BorderRadius.circular(_expanded ? 18 : kCarpetBallSize / 2),
        border: Border.all(color: kCarpetGold, width: _expanded ? 2 : 1.5),
        gradient: _expanded
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kCarpetDeepRed, kCarpetDarkRed, kCarpetPurple],
              )
            : const RadialGradient(
                center: Alignment(-0.3, -0.3),
                colors: [kCarpetDeepRed, kCarpetDarkRed],
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // OverflowBox 让内容始终以展开后的尺寸布局，避免动画中途挤压溢出
      child: _expanded
          ? OverflowBox(
              minWidth: width,
              maxWidth: width,
              minHeight: height,
              maxHeight: height,
              alignment: Alignment.topLeft,
              child: _buildList(pool),
            )
          : _buildBall(),
    );
  }

  /// 缩球态：点击展开
  Widget _buildBall() {
    return InkWell(
      key: const Key('魔毯小球'),
      customBorder: const CircleBorder(),
      onTap: () => setState(() => _expanded = true),
      child: const Center(
        child: Icon(Icons.auto_awesome, color: kCarpetGold, size: 24),
      ),
    );
  }

  /// 展开态：标题栏 + 灵感列表（新的在前，内部滚动）
  Widget _buildList(List<Inspiration> pool) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 顶栏：标题 + 收起按钮
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: kCarpetGold, size: 16),
              const SizedBox(width: 6),
              Text(
                '灵感魔毯 · ${pool.length}',
                style: const TextStyle(
                  fontFamily: 'LXGWWenKai',
                  color: kCarpetGold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              IconButton(
                key: const Key('魔毯收起按钮'),
                icon: const Icon(Icons.close, color: kCarpetGold, size: 18),
                onPressed: () => setState(() => _expanded = false),
              ),
            ],
          ),
        ),
        // 灵感列表
        Expanded(
          child: pool.isEmpty
              ? const Center(
                  child: Text(
                    '魔毯空空如也\n随时速记一条灵感吧',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: pool.length,
                  itemBuilder: (context, i) =>
                      CarpetItem(inspiration: pool[i]),
                ),
        ),
      ],
    );
  }
}

/// 魔毯上的一条灵感：长按拖起，可放到树上章/节标签（DragTarget 在大纲页）
class CarpetItem extends StatelessWidget {
  const CarpetItem({super.key, required this.inspiration});

  final Inspiration inspiration;

  @override
  Widget build(BuildContext context) {
    final tile = _tile();
    // 长按拖拽（列表内普通 Draggable 会与滚动手势冲突）
    return LongPressDraggable<Inspiration>(
      key: Key('魔毯灵感_${inspiration.id}'),
      data: inspiration,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      // 拖起时的浮影：一张发光的小灵感卡
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: kCarpetDeepRed,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kCarpetGold, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: kCarpetGold.withValues(alpha: 0.4),
                blurRadius: 12,
              ),
            ],
          ),
          child: Text(
            inspiration.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'LXGWWenKai',
              color: Colors.white,
              fontSize: 13,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }

  Widget _tile() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kCarpetGold.withValues(alpha: 0.35)),
      ),
      child: Text(
        inspiration.content,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'LXGWWenKai',
          color: Colors.white,
          fontSize: 13,
          height: 1.35,
        ),
      ),
    );
  }
}
