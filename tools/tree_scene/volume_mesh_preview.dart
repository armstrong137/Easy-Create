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
  _Mesh(this.meta, this.data, this.image, this.leafImage) {
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
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.high,
    );
  }
  final Map<String, dynamic> meta;
  final ByteData data;
  final ui.Image image;
  final ui.Image? leafImage;
  late final Float32List normals, bindings, corners;
  late final List<List<double>> nodes;
  late final List<List<int>> edges;
  late final List<double> target, right, up, back;
  late final double scale;
  late final ui.ImageShader shader;
  void dispose() {
    shader.dispose();
    image.dispose();
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
    try {
      return _Mesh(metadata, binary, (await codec.getNextFrame()).image, leaf);
    } finally {
      codec.dispose();
    }
  }

  _Frame deform(double age) {
    final watch = Stopwatch()..start();
    final grown = <List<double>>[];
    final growth = meta['growth'] as List?;
    for (var i = 0; i < nodes.length; i++) {
      final p = nodes[i];
      if (growth != null) {
        final recipe = growth[i] as Map;
        final kind = recipe['kind'];
        if (kind == 'base') {
          grown.add([0, 0, .12 + .38 * _smooth(age)]);
        } else if (kind == 'root') {
          final reach = .30 + .70 * _smooth(age);
          grown.add([
            p[0] * reach,
            p[1] * reach,
            p[2] < .05 ? p[2] : p[2] * (.35 + .65 * _smooth(age)),
          ]);
        } else {
          final parent = recipe['parent'] as int;
          final progress = _smooth(
            (age - (recipe['birth'] as num)) / (recipe['duration'] as num),
          );
          final minimum = kind == 'trunk' ? .12 : .025;
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
    for (final edge in edges) {
      var radial = growth == null
          ? .5 + .5 * _smooth(age)
          : .13 + .87 * _smooth(age);
      if (growth != null) {
        final recipe = growth[edge[1]] as Map;
        if (recipe['kind'] == 'branch' || recipe['kind'] == 'frame') {
          final progress = _smooth(
            (age - (recipe['birth'] as num)) / (recipe['duration'] as num),
          );
          radial *= .08 + .92 * math.sqrt(progress);
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
          .42 +
          .58 * math.max(0, (-.45 * nx - .5 * ny + .74 * nz) / normalLength);
      // 图集以显示空间采样，使用显示空间的明暗调制近似；仍须对照离线光照。
      final channel = (255 * math.pow(light, 1 / 2.2)).round().clamp(0, 255);
      colors[i] = 0xff000000 | (channel << 16) | (channel << 8) | channel;
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
        ),
      );
    }
    final plaques = <_Plaque>[];
    for (final definition in (meta['plaques'] as List? ?? const [])) {
      final life = _smooth(
        (age - (definition['birth'] as num)) / (definition['duration'] as num),
      );
      if (life < .98) continue;
      final anchor = definition['anchor'] as int;
      final offset = definition['offset'] as List;
      final center = List.generate(
        3,
        (axis) => grown[anchor][axis] + (offset[axis] as num),
      );
      plaques.add(
        _Plaque(project(center).point, definition['title'] as String),
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
  _Leaf(this.point, this.anchor, this.depth, this.angle, this.length);
  final Offset point, anchor;
  final double depth, angle, length;
}

class _Plaque {
  _Plaque(this.point, this.title);
  final Offset point;
  final String title;
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
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(factor);
    if (near) canvas.translate(0, -1.5);
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
        width: 2.9,
        height: .25,
      ),
      Paint()
        ..color = const Color(0x284d3d28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .1),
    );
    final paint = Paint()
      ..shader = mesh.shader
      ..filterQuality = FilterQuality.high;
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
      canvas.translate(plaque.point.dx, plaque.point.dy);
      final paper = Path()
        ..moveTo(-.27, -.43)
        ..lineTo(.26, -.42)
        ..lineTo(.28, .40)
        ..lineTo(-.25, .43)
        ..close();
      canvas.drawPath(
        paper,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xffead8ad), Color(0xffd4bd8d)],
          ).createShader(const Rect.fromLTWH(-.3, -.45, .6, .9)),
      );
      // 排版先使用正常字号，再变换回模型单位，避免小字号行高被取整为零。
      canvas.save();
      canvas.scale(.01);
      final characters = plaque.title.split('');
      for (var index = 0; index < characters.length; index++) {
        final text = TextPainter(
          text: TextSpan(
            text: characters[index],
            style: const TextStyle(
              fontFamily: 'LXGWWenKai',
              fontSize: 22,
              height: 1,
              color: Color(0xff30271c),
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
            scale: leaf.length / 346,
            anchorX: 256,
            anchorY: 430,
            translateX: leaf.point.dx,
            translateY: leaf.point.dy,
          ),
      ],
      List.filled(
        leaves.length,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ),
      List.filled(leaves.length, const Color(0xffd9dfbc)),
      BlendMode.modulate,
      null,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  void _wood(Canvas canvas, Paint paint, List<int> order) {
    const batch = 8192;
    for (var start = 0; start < order.length; start += batch) {
      final count = math.min(batch, order.length - start) * 3;
      final points = Float32List(count * 2), uv = Float32List(count * 2);
      final colors = Int32List(count);
      for (var corner = 0; corner < count; corner++) {
        final source = order[start + corner ~/ 3] * 9 + (corner % 3) * 3;
        final index = mesh.corners[source].round();
        points[corner * 2] = frame.points[index * 2];
        points[corner * 2 + 1] = frame.points[index * 2 + 1];
        uv[corner * 2] = mesh.corners[source + 1] * mesh.image.width;
        uv[corner * 2 + 1] = (1 - mesh.corners[source + 2]) * mesh.image.height;
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
    }
  }

  @override
  bool shouldRepaint(covariant _Painter oldDelegate) =>
      oldDelegate.frame != frame;
}
