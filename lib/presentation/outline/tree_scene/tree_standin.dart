import 'package:flutter/material.dart';

int treeStandinIndex(double age) {
  final bounded = age.clamp(0.0, 1.0);
  return (bounded * 5).ceil().clamp(0, 5);
}

class TreeStandin extends StatelessWidget {
  const TreeStandin({super.key, required this.age});

  final double age;

  @override
  Widget build(BuildContext context) {
    final index = treeStandinIndex(age);
    return ColoredBox(
      color: const Color(0xFFFDF6EC),
      child: Semantics(
        image: true,
        label: '魔树静态预览',
        child: Image.asset(
          'assets/tree_scene/standins/age_$index.webp',
          fit: BoxFit.contain,
          alignment: Alignment.center,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
