import 'dart:ui';

import 'package:flutter/material.dart';

/// 玻璃质感"＋"号（定稿：BackdropFilter 模糊 + 动态反光高光）
///
/// 一道斜向高光每几秒扫过一次玻璃面，营造"动态反光"。
class GlassPlusButton extends StatefulWidget {
  const GlassPlusButton({
    super.key,
    required this.onTap,
    required this.semanticLabel,
  });

  final VoidCallback onTap;
  final String semanticLabel;

  @override
  State<GlassPlusButton> createState() => _GlassPlusButtonState();
}

class _GlassPlusButtonState extends State<GlassPlusButton>
    with SingleTickerProviderStateMixin {
  /// 反光扫过动画：4 秒一轮（含停顿），高光斜扫玻璃面
  late final AnimationController _shine = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 52.0;
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        // 玻璃：模糊透出底下的树
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Material(
            color: Colors.white.withValues(alpha: 0.35),
            child: InkWell(
              onTap: widget.onTap,
              child: SizedBox.square(
                dimension: size,
                child: Stack(
                  children: [
                    // 玻璃边缘：上亮下暗的描边模拟厚度
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.18),
                          width: 1.2,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.55),
                            Colors.white.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                    ),
                    // 动态反光：一道斜高光周期性扫过
                    AnimatedBuilder(
                      animation: _shine,
                      builder: (context, _) {
                        // 前 40% 时间扫过，其余时间停在画外
                        final t = (_shine.value / 0.4).clamp(0.0, 1.0);
                        final dx = -size + t * size * 2.4;
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: Transform.rotate(
                            angle: 0.5,
                            child: Container(
                              width: 14,
                              height: size * 1.6,
                              color: Colors.white
                                  .withValues(alpha: 0.35 * (1 - t)),
                            ),
                          ),
                        );
                      },
                    ),
                    // ＋号本体
                    const Center(
                      child: Icon(Icons.add, size: 28, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
