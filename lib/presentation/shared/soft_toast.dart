import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

/// 柔和浮层提示（iOS 质感）：毛玻璃墨色药丸，顶部滑入、停留后淡出。
/// 全局替代 Material SnackBar（用户质感红线：拒绝安卓默认组件）。
void showSoftToast(BuildContext context, String message) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _SoftToast(message: message, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _SoftToast extends StatefulWidget {
  const _SoftToast({required this.message, required this.onDone});

  final String message;
  final VoidCallback onDone;

  @override
  State<_SoftToast> createState() => _SoftToastState();
}

class _SoftToastState extends State<_SoftToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Timer? _stay;

  @override
  void initState() {
    super.initState();
    _fade.forward();
    _stay = Timer(const Duration(milliseconds: 1700), () async {
      await _fade.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _stay?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic);
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.80),
          child: FadeTransition(
            opacity: eased,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, -0.4),
                end: Offset.zero,
              ).animate(eased),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 11,
                    ),
                    color: const Color(0xD92B2018), // 暖墨色 85%
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        fontFamily: 'LXGWWenKai',
                        fontSize: 14,
                        color: Color(0xFFFDF6EC),
                        decoration: TextDecoration.none,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
