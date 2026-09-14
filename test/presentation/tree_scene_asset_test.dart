import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Map<String, dynamic> _readGlbJson(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(data.getUint32(0, Endian.little), 0x46546C67);
  final jsonLength = data.getUint32(12, Endian.little);
  final jsonType = data.getUint32(16, Endian.little);
  expect(jsonType, 0x4E4F534A);
  return jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)).trimRight())
      as Map<String, dynamic>;
}

void main() {
  test('Flutter Web 打包 three.js 的全部运行时依赖', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('assets/tree_scene/vendor/addons/math/'),
      reason: 'KTX2Loader 依赖 ColorSpaces.js，缺失时实时 3D 会启动失败并退回静态图',
    );
    expect(
      File('assets/tree_scene/vendor/addons/math/ColorSpaces.js').existsSync(),
      isTrue,
    );
  });

  test('树干呼吸动画围绕原始比例轻微起伏而不会把骨骼压扁', () {
    final source = File(
      'scripts/build_magic_tree_art_asset.py',
    ).readAsStringSync();
    expect(
      source,
      contains('"idle_breath": ((1, 1.0), (60, 1.012), (120, 1.0))'),
      reason: '骨骼缩放必须围绕 1.0；以 0.0 为中心会让实时树干完全消失',
    );
  });

  test('正式古树使用宽基部与高密度小叶树冠', () {
    final source = File(
      'scripts/build_magic_tree_art_asset.py',
    ).readAsStringSync();
    expect(source, contains('MATURE_TOP_SPREAD = 1.34'));
    expect(source, contains('MATURE_BASE_FLARE = 2.45'));
    expect(source, contains('limit: int = 2600'));
    final refinement = File(
      'scripts/refine_magic_tree_blend.py',
    ).readAsStringSync();
    expect(refinement, contains('TARGET_LEAF_ANCHORS = 2600'));
  });

  test('正式魔树 GLB、源文件与六张回退图齐全', () {
    expect(
      File(
        'assets/source/magic_tree/blender/magic_tree_master.blend',
      ).existsSync(),
      isTrue,
    );
    expect(File('assets/3d/magic_tree/magic_tree.glb').existsSync(), isTrue);
    for (var i = 0; i < 6; i++) {
      expect(
        File('assets/tree_scene/standins/age_$i.webp').existsSync(),
        isTrue,
        reason: '缺少 age_$i.webp',
      );
    }
  });

  test('正式二维树图和透明枝牌素材齐全', () {
    for (var i = 0; i < 6; i++) {
      final file = File('assets/tree_scene/illustrated/age_$i.png');
      expect(file.existsSync(), isTrue, reason: '缺少正式二维树 age_$i.png');
      final image = img.decodePng(file.readAsBytesSync());
      expect(image, isNotNull);
      expect(image!.width, 941);
      expect(image.height, 1672);
    }

    final branch = img.decodePng(
      File(
        'assets/tree_scene/illustrated/chapter_branch.png',
      ).readAsBytesSync(),
    )!;
    expect(branch.width, 1536);
    expect(branch.height, 1024);
    var transparent = 0;
    var opaque = 0;
    var rightMarginOpaque = 0;
    for (var y = 0; y < branch.height; y += 4) {
      for (var x = 0; x < branch.width; x += 4) {
        final alpha = branch.getPixel(x, y).a;
        if (alpha <= 8) {
          transparent += 1;
        } else {
          opaque += 1;
          if (x > branch.width * 0.92) rightMarginOpaque += 1;
        }
      }
    }
    expect(transparent / (transparent + opaque), greaterThan(0.7));
    expect(rightMarginOpaque, 0, reason: '枝牌树干侧必须保留透明余量，不能硬切到画布边缘');
  });

  test('正式魔树使用批准的古树阔叶美术母版', () {
    final gltf = _readGlbJson('assets/3d/magic_tree/magic_tree.glb');
    final nodes = (gltf['nodes'] as List).cast<Map<String, dynamic>>();
    final root = nodes.singleWhere((node) => node['name'] == 'MagicTreeRoot');
    final extras = (root['extras'] as Map).cast<String, dynamic>();

    expect(extras['formal_asset'], isTrue, reason: '技术占位树不得作为正式资产交付');
    expect(extras['art_style'], 'ancient_broadleaf_v2');
    expect(
      extras['asset_origin'],
      'polyhaven_island_tree_01_cc0',
      reason: '正式树必须来自经批准的真实扫描母版，不能退回程序化曲线树',
    );
    expect(extras['leaf_emergence_mode'], 'runtime_crown_guide_instances');
    expect(extras['main_branch_count'], inInclusiveRange(5, 7));
    expect(
      extras['tertiary_twig_count'],
      greaterThanOrEqualTo(44),
      reason: '正式古树需要连续的末梢枝层，不能以粗枝截面直接结束',
    );
    expect(
      extras['leaf_card_count'],
      greaterThanOrEqualTo(900),
      reason: '成熟树冠需要足够密度的小阔叶形成连续轮廓',
    );

    final nodeNames = nodes.map((node) => node['name']).toSet();
    expect(
      nodeNames,
      containsAll(<String>[
        'RootFlare',
        'ExposedRoots',
        'MossPatches',
        'GroundDebris',
        'MagicVeins',
        'LeafClusters',
        'TertiaryTwigs',
      ]),
    );

    final materialNames = (gltf['materials'] as List)
        .cast<Map<String, dynamic>>()
        .map((material) => material['name'])
        .toSet();
    expect(
      materialNames,
      containsAll(<String>[
        'BarkOldPBR',
        'LeafBroadPBR',
        'MossPBR',
        'GroundPBR',
        'MagicVeinPBR',
      ]),
    );
  });

  test('六张回退图四周透明且没有矩形底片', () {
    for (var i = 0; i < 6; i++) {
      final file = File('assets/tree_scene/standins/age_$i.webp');
      final image = img.decodeWebP(file.readAsBytesSync());
      expect(image, isNotNull, reason: 'age_$i.webp 必须可解码');
      final corners = [
        image!.getPixel(0, 0),
        image.getPixel(image.width - 1, 0),
        image.getPixel(0, image.height - 1),
        image.getPixel(image.width - 1, image.height - 1),
      ];
      expect(
        corners.every((pixel) => pixel.a <= 8),
        isTrue,
        reason: 'age_$i.webp 四角必须透明，否则静态回退会出现矩形分割感',
      );
    }
  });

  test('成熟树树冠丰满且四周保留安全边', () {
    final image = img.decodeWebP(
      File('assets/tree_scene/standins/age_5.webp').readAsBytesSync(),
    )!;
    var left = image.width;
    var right = 0;
    var top = image.height;
    var bottom = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).a <= 20) continue;
        left = x < left ? x : left;
        right = x > right ? x : right;
        top = y < top ? y : top;
        bottom = y > bottom ? y : bottom;
      }
    }
    final safeX = image.width * 0.025;
    expect(left, greaterThanOrEqualTo(safeX), reason: '成熟树不能碰到左边界');
    expect(right, lessThanOrEqualTo(image.width - safeX), reason: '成熟树不能碰到右边界');

    final crownBottom = top + ((bottom - top) * 0.65).round();
    var rowSpanTotal = 0.0;
    var populatedRows = 0;
    for (var y = top; y <= crownBottom; y++) {
      var rowLeft = image.width;
      var rowRight = 0;
      for (var x = left; x <= right; x++) {
        if (image.getPixel(x, y).a <= 20) continue;
        rowLeft = x < rowLeft ? x : rowLeft;
        rowRight = x > rowRight ? x : rowRight;
      }
      if (rowLeft > rowRight) continue;
      rowSpanTotal += (rowRight - rowLeft + 1) / (right - left + 1);
      populatedRows++;
    }
    expect(
      rowSpanTotal / populatedRows,
      greaterThanOrEqualTo(0.58),
      reason: '成熟树冠必须宽而丰满，不能是烛台或仙人掌轮廓',
    );
  });
}
