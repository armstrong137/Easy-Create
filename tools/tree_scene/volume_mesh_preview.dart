import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('volumeProofMetrics')
external set _metrics(JSAny? value);
@JS('volumeProofPaint')
external set _paintMetrics(JSAny? value);
@JS('setVolumeProofAge')
external set _setAge(JSFunction? value);

// 独立Web验证，不引用正式页面、业务仓库或树龄阶段图片。
void main() => runApp(const MaterialApp(home: _Preview()));

double _smooth(double value) {
  final t = value.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

class _Mesh {
  _Mesh(this.meta, this.data, this.image, this.leafImage, this.extraImages) {
    normals = section('normals');
    bindings = section('bindings');
    corners = section('corners');
    nodes = (meta['nodes'] as List)
        .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
        .toList();
    edges = (meta['edges'] as List)
        .map((p) => (p as List).cast<int>())
        .toList();
    final camera = meta['camera'] as Map<String, dynamic>;
    target = (camera['target'] as List)
        .cast<num>()
        .map((v) => v.toDouble())
        .toList();
    right = (camera['right'] as List)
        .cast<num>()
        .map((v) => v.toDouble())
        .toList();
    up = (camera['up'] as List).cast<num>().map((v) => v.toDouble()).toList();
    back = (camera['back'] as List)
        .cast<num>()
        .map((v) => v.toDouble())
        .toList();
    scale = (camera['scale'] as num).toDouble();
    // 本入口仅验证Web；着色器持有独立图像句柄，避免释放借用图集。
    shader = ui.ImageShader(
      image.clone(),
      meta['repeatTexture'] == true ? TileMode.repeated : TileMode.clamp,
      meta['repeatTexture'] == true ? TileMode.repeated : TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.high,
    );
    extraShaders = [
      for (final texture in extraImages)
        ui.ImageShader(
          texture.clone(),
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.high,
        ),
    ];
  }
  final Map<String, dynamic> meta;
  final ByteData data;
  final ui.Image image;
  final ui.Image? leafImage;
  final List<ui.Image> extraImages;
  late final List<ui.ImageShader> extraShaders;
  ui.Image texture(int index) => index == 0 ? image : extraImages[index - 1];
  ui.ImageShader textureShader(int index) =>
      index == 0 ? shader : extraShaders[index - 1];
  late final Float32List normals, bindings, corners;
  late final List<List<double>> nodes;
  late final List<List<int>> edges;
  late final List<double> target, right, up, back;
  late final double scale;
  late final ui.ImageShader shader;
  void dispose() {
    shader.dispose();
    image.dispose();
    for (final value in extraShaders) {
      value.dispose();
    }
    for (final value in extraImages) {
      value.dispose();
    }
    leafImage?.dispose();
  }

  int get count => meta['vertexCount'] as int;
  Float32List section(String name) {
    final info = (meta['sections'] as Map)[name] as Map;
    return Float32List.view(
      data.buffer,
      data.offsetInBytes + (info['offset'] as int),
      info['length'] as int,
    );
  }

  static Future<_Mesh> load() async {
    Future<ByteData> read(String name) async {
      final response = await web.window
          .fetch(Uri.base.resolve('proof/$name').toString().toJS)
          .toDart;
      if (!response.ok) throw StateError('资源加载失败：$name ${response.status}');
      return ByteData.view((await response.arrayBuffer().toDart).toDart);
    }

    final metaBytes = await read('mesh.json');
    final metadata =
        jsonDecode(
              utf8.decode(
                metaBytes.buffer.asUint8List(
                  metaBytes.offsetInBytes,
                  metaBytes.lengthInBytes,
                ),
              ),
            )
            as Map<String, dynamic>;
    final binary = await read('mesh.bin');
    final bytes = await read('baked-bark.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    ui.Image? leaf;
    if (metadata.containsKey('leaves')) {
      final leafBytes = await read('leaf.png');
      final leafCodec = await ui.instantiateImageCodec(
        leafBytes.buffer.asUint8List(),
      );
      leaf = (await leafCodec.getNextFrame()).image;
      leafCodec.dispose();
    }
    final extra = <ui.Image>[];
    for (final name in (metadata['extraTextures'] as List? ?? const [])) {
      final bytes = await read(name as String);
      final decoder = await ui.instantiateImageCodec(
        bytes.buffer.asUint8List(),
      );
      extra.add((await decoder.getNextFrame()).image);
      decoder.dispose();
    }
    try {
      return _Mesh(
        metadata,
        binary,
        (await codec.getNextFrame()).image,
        leaf,
        extra,
      );
    } finally {
      codec.dispose();
    }
  }

  _Frame deform(double age) {
    final watch = Stopwatch()..start();
    final grown = <List<double>>[];
    final growth = meta['growth'] as List?;
    final poses = meta['poseFrames'] as List?;
    Map? firstPose, lastPose;
    var poseProgress = 0.0;
    if (poses != null) {
      var index = 0;
      while (index < poses.length - 2 &&
          age > (poses[index + 1]['age'] as num)) {
        index++;
      }
      firstPose = poses[index] as Map;
      lastPose = poses[index + 1] as Map;
      poseProgress = _smooth(
        (age - (firstPose['age'] as num)) /
            ((lastPose['age'] as num) - (firstPose['age'] as num)),
      );
    }
    for (var i = 0; i < nodes.length; i++) {
      final p = nodes[i];
      if (firstPose != null && lastPose != null) {
        final a = firstPose['nodes'][i] as List,
            b = lastPose['nodes'][i] as List;
        grown.add(
          List.generate(
            3,
            (axis) =>
                (a[axis] as num).toDouble() +
                ((b[axis] as num) - (a[axis] as num)) * poseProgress,
          ),
        );
      } else if (growth != null) {
        final recipe = growth[i] as Map;
        final kind = recipe['kind'];
        if (kind == 'base') {
          grown.add([0, 0, .045 + .335 * _smooth(age)]);
        } else if (kind == 'root') {
          final reach = .11 + .89 * _smooth(age);
          grown.add([
            p[0] * reach,
            p[1] * reach,
            p[2] * (.10 + .90 * _smooth(age)),
          ]);
        } else {
          final parent = recipe['parent'] as int;
          final progress = _smooth(
            (age - (recipe['birth'] as num)) / (recipe['duration'] as num),
          );
          final minimum = kind == 'trunk' ? .21 : .003;
          final reach = minimum + (1 - minimum) * progress;
          grown.add(
            List.generate(
              3,
              (axis) =>
                  grown[parent][axis] + (p[axis] - nodes[parent][axis]) * reach,
            ),
          );
        }
      } else if (i >= 11) {
        grown.add([p[0] * (.75 + .25 * age), p[1] * (.75 + .25 * age), p[2]]);
      } else {
        final branch = i >= 5 && i <= 10;
        final reach = branch ? .35 + .65 * _smooth(age) : .75 + .25 * age;
        grown.add([
          p[0] * reach,
          p[1] * reach,
          .7 + (p[2] - .7) * (.65 + .35 * age),
        ]);
      }
    }
    final rotations = <List<double>>[];
    final radialScales = <double>[];
    for (var edgeIndex = 0; edgeIndex < edges.length; edgeIndex++) {
      final edge = edges[edgeIndex];
      var radial = growth == null
          ? .5 + .5 * _smooth(age)
          : .055 + .945 * _smooth(age);
      if (firstPose != null && lastPose != null) {
        final a = firstPose['radial'][edgeIndex] as num,
            b = lastPose['radial'][edgeIndex] as num;
        radial = a.toDouble() + (b - a) * poseProgress;
      } else if (growth != null) {
        final recipe = growth[edge[1]] as Map;
        if (recipe['kind'] == 'branch' || recipe['kind'] == 'frame') {
          final progress = _smooth(
            (age - (recipe['birth'] as num)) / (recipe['duration'] as num),
          );
          radial *= .025 + .975 * math.sqrt(progress);
        }
      }
      radialScales.add(radial);
      final a = nodes[edge[0]], b = nodes[edge[1]];
      final ga = grown[edge[0]], gb = grown[edge[1]];
      var rx = b[0] - a[0], ry = b[1] - a[1], rz = b[2] - a[2];
      var tx = gb[0] - ga[0], ty = gb[1] - ga[1], tz = gb[2] - ga[2];
      final rl = math.sqrt(rx * rx + ry * ry + rz * rz),
          tl = math.sqrt(tx * tx + ty * ty + tz * tz);
      rx /= rl;
      ry /= rl;
      rz /= rl;
      tx /= tl;
      ty /= tl;
      tz /= tl;
      final x = ry * tz - rz * ty, y = rz * tx - rx * tz, z = rx * ty - ry * tx;
      final k = 1 / (1 + rx * tx + ry * ty + rz * tz);
      rotations.add([
        1 - (y * y + z * z) * k,
        -z + x * y * k,
        y + x * z * k,
        z + x * y * k,
        1 - (x * x + z * z) * k,
        -x + y * z * k,
        -y + x * z * k,
        x + y * z * k,
        1 - (x * x + y * y) * k,
      ]);
    }
    final world = Float32List(count * 3);
    final projected = Float32List(count * 2), depths = Float32List(count);
    final colors = Int32List(count);
    final kinds = meta['vertexKinds'] as List?;
    for (var i = 0; i < count; i++) {
      var px = 0.0, py = 0.0, pz = 0.0, nx = 0.0, ny = 0.0, nz = 0.0;
      final normalX = normals[i * 3],
          normalY = normals[i * 3 + 1],
          normalZ = normals[i * 3 + 2];
      for (var slot = 0; slot < 3; slot++) {
        final offset = i * 18 + slot * 6;
        final edge = bindings[offset].round(),
            t = bindings[offset + 1],
            weight = bindings[offset + 5];
        final ox = bindings[offset + 2] * radialScales[edge],
            oy = bindings[offset + 3] * radialScales[edge],
            oz = bindings[offset + 4] * radialScales[edge];
        final a = grown[edges[edge][0]],
            b = grown[edges[edge][1]],
            r = rotations[edge];
        px +=
            (a[0] + (b[0] - a[0]) * t + r[0] * ox + r[1] * oy + r[2] * oz) *
            weight;
        py +=
            (a[1] + (b[1] - a[1]) * t + r[3] * ox + r[4] * oy + r[5] * oz) *
            weight;
        pz +=
            (a[2] + (b[2] - a[2]) * t + r[6] * ox + r[7] * oy + r[8] * oz) *
            weight;
        nx += (r[0] * normalX + r[1] * normalY + r[2] * normalZ) * weight;
        ny += (r[3] * normalX + r[4] * normalY + r[5] * normalZ) * weight;
        nz += (r[6] * normalX + r[7] * normalY + r[8] * normalZ) * weight;
      }
      world[i * 3] = px;
      world[i * 3 + 1] = py;
      world[i * 3 + 2] = pz;
      final x = px - target[0], y = py - target[1], z = pz - target[2];
      projected[i * 2] = x * right[0] + y * right[1] + z * right[2];
      projected[i * 2 + 1] = -(x * up[0] + y * up[1] + z * up[2]);
      depths[i] = x * back[0] + y * back[1] + z * back[2];
      final normalLength = math.sqrt(nx * nx + ny * ny + nz * nz);
      final light =
          .25 +
          .75 * math.max(0, (-.45 * nx - .5 * ny + .74 * nz) / normalLength);
      // 图集以显示空间采样，使用显示空间的明暗调制近似；仍须对照离线光照。
      final channel = (255 * math.pow(light, 1 / 2.2)).round().clamp(0, 255);
      colors[i] = meta['unlitTexture'] == true
          ? 0xffffffff
          : 0xff000000 | (channel << 16) | (channel << 8) | channel;
      if (kinds != null) {
        final kind = kinds[i] as int;
        if (kind == 1) {
          colors[i] = 0xffb3d5ae;
        } else if (kind == 0) {
          colors[i] = Color.lerp(
            const Color(0xffa2b88a),
            const Color(0xffcbd7d1),
            _smooth(age),
          )!.toARGB32();
        } else {
          colors[i] = 0xffcbd7d1;
        }
      }
    }
    final visible = <int>[];
    final triangleDepths = Float32List(corners.length ~/ 9);
    for (var i = 0; i < corners.length; i += 9) {
      final a = corners[i].round(),
          b = corners[i + 3].round(),
          c = corners[i + 6].round();
      final cross =
          (projected[b * 2] - projected[a * 2]) *
              (projected[c * 2 + 1] - projected[a * 2 + 1]) -
          (projected[b * 2 + 1] - projected[a * 2 + 1]) *
              (projected[c * 2] - projected[a * 2]);
      if (cross >= 0) continue;
      visible.add(i ~/ 9);
      triangleDepths[i ~/ 9] = (depths[a] + depths[b] + depths[c]) / 3;
    }
    visible.sort((a, b) => triangleDepths[a].compareTo(triangleDepths[b]));
    ({Offset point, double depth}) project(List<double> p) {
      final x = p[0] - target[0], y = p[1] - target[1], z = p[2] - target[2];
      return (
        point: Offset(
          x * right[0] + y * right[1] + z * right[2],
          -(x * up[0] + y * up[1] + z * up[2]),
        ),
        depth: x * back[0] + y * back[1] + z * back[2],
      );
    }

    final foliage = <_Leaf>[];
    for (final definition in (meta['leaves'] as List? ?? const [])) {
      final life = _smooth(
        (age - (definition['birth'] as num)) / (definition['duration'] as num),
      );
      if (life <= .001) continue;
      final edge = definition['edge'] as int,
          t = (definition['t'] as num).toDouble();
      final a = grown[edges[edge][0]],
          b = grown[edges[edge][1]],
          r = rotations[edge];
      final anchor = List.generate(
        3,
        (axis) => a[axis] + (b[axis] - a[axis]) * t,
      );
      final offset = definition['offset'] as List;
      final p = List.generate(
        3,
        (axis) =>
            anchor[axis] +
            life *
                (r[axis * 3] * (offset[0] as num) +
                    r[axis * 3 + 1] * (offset[1] as num) +
                    r[axis * 3 + 2] * (offset[2] as num)),
      );
      final projectedLeaf = project(p), projectedAnchor = project(anchor);
      foliage.add(
        _Leaf(
          projectedLeaf.point,
          projectedAnchor.point,
          projectedLeaf.depth,
          (definition['angle'] as num).toDouble(),
          (definition['length'] as num) * life,
          definition['variant'] as int? ?? 0,
        ),
      );
    }
    final plaques = <_Plaque>[];
    for (final definition in (meta['plaques'] as List? ?? const [])) {
      final life = _smooth(
        (age - (definition['birth'] as num)) / (definition['duration'] as num),
      );
      final opacity = _smooth((life - .6) / .4);
      if (opacity <= .001) continue;
      final indices = (definition['corners'] as List).cast<int>();
      final center = List.generate(
        3,
        (axis) =>
            indices.fold<double>(0, (sum, index) => sum + grown[index][axis]) /
            4,
      );
      // 纸面四角取自当前木框角点，内缩到框内；成长时不使用固定屏幕矩形。
      final points = [
        for (final index in indices)
          project(
            List.generate(
              3,
              (axis) =>
                  center[axis] + (grown[index][axis] - center[axis]) * .79,
            ),
          ).point,
      ];
      plaques.add(
        _Plaque(
          points,
          definition['title'] as String,
          definition['unroll'] == true ? 1 : opacity,
          definition['unroll'] == true ? opacity : 1,
        ),
      );
    }
    var error = 0.0;
    for (final sample in meta['samples'] as List) {
      if ((sample['age'] as num).toDouble() != age) continue;
      for (final vertex in sample['vertices'] as List) {
        final index = vertex['index'] as int;
        for (var axis = 0; axis < 3; axis++) {
          error = math.max(
            error,
            (world[index * 3 + axis] - (vertex['position'][axis] as num)).abs(),
          );
        }
      }
    }
    return _Frame(
      projected,
      colors,
      visible,
      watch.elapsedMicroseconds / 1000,
      error,
      age,
      triangleDepths,
      foliage,
      plaques,
    );
  }
}

class _Frame {
  _Frame(
    this.points,
    this.colors,
    this.order,
    this.milliseconds,
    this.referenceError,
    this.age,
    this.depths,
    this.leaves,
    this.plaques,
  );
  final Float32List points;
  final Int32List colors;
  final List<int> order;
  final double milliseconds, referenceError, age;
  final Float32List depths;
  final List<_Leaf> leaves;
  final List<_Plaque> plaques;
}

class _Leaf {
  _Leaf(
    this.point,
    this.anchor,
    this.depth,
    this.angle,
    this.length,
    this.variant,
  );
  final Offset point, anchor;
  final double depth, angle, length;
  final int variant;
}

class _Plaque {
  _Plaque(this.corners, this.title, this.opacity, this.reveal);
  final List<Offset> corners;
  final String title;
  final double opacity, reveal;
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  _Mesh? mesh;
  String? error;
  bool near = false;
  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
      value: 1,
    )..addListener(() => setState(() {}));
    // 逐帧采集仍计算真实网格，不切换树龄图片。
    _setAge = ((JSNumber value) {
      controller.stop();
      controller.value = value.toDartDouble;
    }).toJS;
    _Mesh.load()
        .then((value) {
          if (mounted) {
            setState(() => mesh = value);
          } else {
            value.dispose();
          }
        })
        .catchError((Object value) {
          _metrics = {'error': value.toString()}.jsify();
          if (mounted) setState(() => error = value.toString());
        });
  }

  @override
  void dispose() {
    controller.dispose();
    _setAge = null;
    mesh?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loaded = mesh;
    final age = controller.value;
    final frame = loaded?.deform(age);
    if (loaded != null && frame != null) {
      _metrics = {
        'age': age,
        'vertices': loaded.count,
        'visibleTriangles': frame.order.length,
        'computeMs': frame.milliseconds,
        'referenceError': frame.referenceError,
        'leaves': frame.leaves.length,
        'plaques': frame.plaques.length,
        'foliageParts': loaded.meta['foliageParts'] ?? 0,
      }.jsify();
    }
    return Scaffold(
      backgroundColor: const Color(0xfff7f0e3),
      appBar: AppBar(
        title: const Text('独立Flutter二维网格验证'),
        backgroundColor: const Color(0xfff7f0e3),
      ),
      body: loaded == null
          ? Center(child: Text(error ?? '正在加载网格与图集'))
          : Column(
              children: [
                Text(
                  '树龄 ${age.toStringAsFixed(3)} · 时间 ${(age * 10).toStringAsFixed(1)}s · 实际网格绘制',
                ),
                Expanded(
                  child: CustomPaint(
                    painter: _Painter(loaded, frame!, near),
                    child: const SizedBox.expand(),
                  ),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => near = !near),
                      child: Text(near ? '返回全景' : '枝牌近景'),
                    ),
                    for (final item in [
                      ('较细状态', 0.0),
                      ('中间状态', .5),
                      ('完整片段', 1.0),
                    ])
                      TextButton(
                        onPressed: () {
                          controller.stop();
                          controller.value = item.$2;
                        },
                        child: Text(item.$1),
                      ),
                    TextButton(
                      onPressed: () => controller.forward(from: 0),
                      child: const Text('连续形变'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter(this.mesh, this.frame, this.near);
  final _Mesh mesh;
  final _Frame frame;
  final bool near;
  @override
  void paint(Canvas canvas, Size size) {
    final watch = Stopwatch()..start();
    final factor =
        (near ? 2.0 : 1.0) *
        math.min(
          size.height / mesh.scale,
          size.width / (mesh.scale * 600 / 760),
        );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(factor);
    if (near) {
      final offset = mesh.meta['nearOffset'] as List?;
      canvas.translate(
        (offset?[0] as num?)?.toDouble() ?? 0,
        (offset?[1] as num?)?.toDouble() ?? -1.5,
      );
    }
    if (mesh.meta['groundShadow'] != false) {
      final rootWidth = mesh.meta['rootWidth'] as List?;
      final half = frame.age <= .5 ? 0 : 1;
      final rootScale = rootWidth == null
          ? 1.0
          : (rootWidth[half] as num) +
                ((rootWidth[half + 1] as num) - (rootWidth[half] as num)) *
                    _smooth((frame.age - half * .5) * 2);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            -(mesh.target[0] * mesh.right[0] +
                mesh.target[1] * mesh.right[1] +
                mesh.target[2] * mesh.right[2]),
            mesh.target[0] * mesh.up[0] +
                mesh.target[1] * mesh.up[1] +
                mesh.target[2] * mesh.up[2],
          ),
          width: 2.9 * rootScale,
          height: .25 * rootScale,
        ),
        Paint()
          ..color = const Color(0x284d3d28)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, .1 * rootScale),
      );
    }
    final paint = Paint()
      ..shader = mesh.shader
      ..filterQuality = FilterQuality.high;
    if (mesh.meta['mutedIllustration'] == true) {
      // 原图像素不变，以统一材质降低金黄色饱和度，保留原始光向和透明度。
      const s = .62,
          r = .2126 * (1 - s),
          g = .7152 * (1 - s),
          b = .0722 * (1 - s);
      paint.colorFilter = const ColorFilter.matrix([
        r + s,
        g,
        b,
        0,
        0,
        r,
        g + s,
        b,
        0,
        0,
        r,
        g,
        b + s,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    }
    if (frame.leaves.isEmpty) {
      _wood(canvas, paint, frame.order);
    } else {
      // 深度分层合批，叶簇与木质共同遮挡；不把所有叶片硬贴到最前面。
      var low = double.infinity, high = double.negativeInfinity;
      for (final index in frame.order) {
        low = math.min(low, frame.depths[index]);
        high = math.max(high, frame.depths[index]);
      }
      for (final leaf in frame.leaves) {
        low = math.min(low, leaf.depth);
        high = math.max(high, leaf.depth);
      }
      int bucket(double depth) =>
          ((depth - low) / (high - low) * 23).floor().clamp(0, 23);
      final woodBins = List.generate(24, (_) => <int>[]),
          leafBins = List.generate(24, (_) => <_Leaf>[]);
      for (final index in frame.order) {
        woodBins[bucket(frame.depths[index])].add(index);
      }
      for (final leaf in frame.leaves) {
        leafBins[bucket(leaf.depth)].add(leaf);
      }
      for (var layer = 0; layer < 24; layer++) {
        _wood(canvas, paint, woodBins[layer]);
        _foliage(canvas, leafBins[layer]);
      }
    }
    for (final plaque in frame.plaques) {
      canvas.save();
      final paper = Path()
        ..addPolygon([
          Offset.lerp(plaque.corners[3], plaque.corners[0], plaque.reveal)!,
          Offset.lerp(plaque.corners[2], plaque.corners[1], plaque.reveal)!,
          plaque.corners[2],
          plaque.corners[3],
        ], true);
      canvas.drawPath(
        paper,
        Paint()
          ..shader = LinearGradient(
            colors: [
              const Color(0xffead8ad).withValues(alpha: plaque.opacity),
              const Color(0xffd4bd8d).withValues(alpha: plaque.opacity),
            ],
          ).createShader(paper.getBounds()),
      );
      // 纸面保持不透明；文字在完整框坐标排版，再由展开区域裁剪。
      canvas.clipPath(paper);
      final top = plaque.corners[0],
          across = (plaque.corners[1] - top) / .62,
          down = (plaque.corners[3] - top) / .94;
      canvas.transform(
        Float64List.fromList([
          across.dx,
          across.dy,
          0,
          0,
          down.dx,
          down.dy,
          0,
          0,
          0,
          0,
          1,
          0,
          top.dx,
          top.dy,
          0,
          1,
        ]),
      );
      canvas.translate(.31, .47);
      // 排版先使用正常字号，再变换回模型单位，避免小字号行高被取整为零。
      canvas.save();
      canvas.scale(.01);
      final characters = plaque.title.split('');
      for (var index = 0; index < characters.length; index++) {
        final text = TextPainter(
          text: TextSpan(
            text: characters[index],
            style: TextStyle(
              fontFamily: 'LXGWWenKai',
              fontSize: 22,
              height: 1,
              color: const Color(0xff30271c).withValues(alpha: plaque.opacity),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(
          canvas,
          Offset(
            -text.width / 2,
            (index - (characters.length - 1) / 2) * 25 - text.height / 2,
          ),
        );
        text.dispose();
      }
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();
    _paintMetrics = {
      'age': frame.age,
      'recordMs': watch.elapsedMicroseconds / 1000,
    }.jsify();
  }

  void _foliage(Canvas canvas, List<_Leaf> leaves) {
    final image = mesh.leafImage;
    if (image == null || leaves.isEmpty) return;
    final atlas = mesh.meta['leafAtlas'] as Map?;
    final columns = atlas?['columns'] as int? ?? 1,
        rows = atlas?['rows'] as int? ?? 1;
    final width = image.width / columns, height = image.height / rows;
    final anchor =
        atlas?['anchor'] as List? ?? [256 / image.width, 430 / image.height];
    final blade = (atlas?['blade'] as num?)?.toDouble() ?? 346 / image.height;
    final stems = Path();
    for (final leaf in leaves) {
      stems.moveTo(leaf.anchor.dx, leaf.anchor.dy);
      stems.lineTo(leaf.point.dx, leaf.point.dy);
    }
    canvas.drawPath(
      stems,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .006
        ..color = const Color(0xff646039),
    );
    canvas.drawAtlas(
      image,
      [
        for (final leaf in leaves)
          ui.RSTransform.fromComponents(
            rotation: leaf.angle,
            scale: leaf.length / (height * blade),
            anchorX: width * (anchor[0] as num),
            anchorY: height * (anchor[1] as num),
            translateX: leaf.point.dx,
            translateY: leaf.point.dy,
          ),
      ],
      [
        for (final leaf in leaves)
          Rect.fromLTWH(
            (leaf.variant % columns) * width,
            (leaf.variant ~/ columns) * height,
            width,
            height,
          ),
      ],
      List.filled(leaves.length, const Color(0xffd0d4af)),
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _wood(Canvas canvas, Paint paint, List<int> order) {
    const batch = 8192;
    final textures = mesh.meta['triangleTextures'] as List?;
    final styles = mesh.meta['textureStyles'] as List?;
    var start = 0;
    while (start < order.length) {
      final textureIndex = textures == null ? 0 : textures[order[start]] as int;
      var end = math.min(order.length, start + batch);
      if (textures != null) {
        end = start + 1;
        while (end < order.length &&
            end < start + batch &&
            textures[order[end]] == textureIndex) {
          end++;
        }
      }
      final texture = mesh.texture(textureIndex);
      paint.shader = mesh.textureShader(textureIndex);
      if (styles != null) {
        final style = styles[textureIndex];
        final wood = style == 'wood' || style == 'frame';
        // 幼木降低原树皮对比度，保留同一透明材质；不切换整树或树龄图片。
        final contrast = wood ? .42 + .58 * _smooth(frame.age) : 1.0;
        final tint = style == 'frame'
            ? [.67, .75, .73]
            : wood
            ? [.85, .84, .80]
            : [.72, .83, .67];
        final juvenile = [109.0, 92.0, 63.0];
        const saturation = .72;
        final grey = [.2126, .7152, .0722];
        paint.colorFilter = ColorFilter.matrix([
          for (var row = 0; row < 3; row++) ...[
            for (var col = 0; col < 3; col++)
              (grey[col] * (1 - saturation) + (row == col ? saturation : 0)) *
                  tint[row] *
                  contrast,
            0,
            juvenile[row] * (1 - contrast),
          ],
          0,
          0,
          0,
          1,
          0,
        ]);
      }
      final count = (end - start) * 3;
      final points = Float32List(count * 2), uv = Float32List(count * 2);
      final colors = Int32List(count);
      for (var corner = 0; corner < count; corner++) {
        final source = order[start + corner ~/ 3] * 9 + (corner % 3) * 3;
        final index = mesh.corners[source].round();
        points[corner * 2] = frame.points[index * 2];
        points[corner * 2 + 1] = frame.points[index * 2 + 1];
        uv[corner * 2] = mesh.corners[source + 1] * texture.width;
        uv[corner * 2 + 1] = (1 - mesh.corners[source + 2]) * texture.height;
        colors[corner] = frame.colors[index];
      }
      final vertices = ui.Vertices.raw(
        ui.VertexMode.triangles,
        points,
        textureCoordinates: uv,
        colors: colors,
      );
      canvas.drawVertices(vertices, BlendMode.modulate, paint);
      vertices.dispose();
      start = end;
    }
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) =>
      oldDelegate.frame != frame;
}
