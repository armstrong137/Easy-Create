"""独立干根/分叉连通体验证：新建场景，绝不读取或覆盖旧母版。"""
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
BAKED = '--baked' in sys.argv
OUT = ROOT / ("build/qa/volume-proof-baked" if BAKED else "build/qa/volume-proof")
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

# 同一边图生成封闭连接体，分叉和根颈不再由互相覆盖的平面片组成。
nodes = [
    (0, 0, .70), (-.08, 0, 1.35), (.10, .04, 2.15),
    (.02, .08, 3.0), (.12, .05, 3.8),
    (-.65, -.02, 1.65), (-1.30, .08, 2.18), (-1.65, .1, 2.45),
    (.70, .02, 2.45), (1.20, .05, 3.0), (1.38, .1, 3.35),
    (-.55, -.08, .20), (-1.35, -.15, .05),
    (.60, -.10, .18), (1.45, -.20, .05),
    (.06, -.55, .15), (.25, -1.05, .04),
    (-.1, .55, .15), (-.35, .95, .04),
]
edges = [(0, 1), (1, 2), (2, 3), (3, 4),
         (1, 5), (5, 6), (6, 7), (2, 8), (8, 9), (9, 10),
         (0, 11), (11, 12), (0, 13), (13, 14),
         (0, 15), (15, 16), (0, 17), (17, 18)]
radii = [.44, .36, .28, .19, .045, .24, .13, .025,
         .20, .11, .025, .28, .04, .29, .04, .26, .035, .24, .035]
# 封闭节点球与锥形枝段互相穿入，再做真实体积并集，避免高价Skin节点断开。
pieces = []
for p, radius in zip(nodes, radii):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=radius, location=p)
    pieces.append(bpy.context.object)
for a, b in edges:
    start, end = Vector(nodes[a]), Vector(nodes[b])
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=radii[a], radius2=radii[b],
        depth=(end-start).length, location=(start+end)/2)
    piece = bpy.context.object
    piece.rotation_euler = (end-start).to_track_quat('Z', 'Y').to_euler()
    pieces.append(piece)
bpy.ops.object.select_all(action='DESELECT')
for piece in pieces:
    piece.select_set(True)
bpy.context.view_layer.objects.active = pieces[0]
bpy.ops.object.join()
control = bpy.context.object
control.name = "独立封闭枝段体积"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
union = control.modifiers.new("干根分叉体积并集", "REMESH")
union.mode = 'VOXEL'
union.voxel_size = .045
union.use_smooth_shade = True
relax = control.modifiers.new("接头表面平滑", "SMOOTH")
relax.factor = .7
relax.iterations = 4
sub = control.modifiers.new("圆润截面", "SUBSURF")
sub.levels = 1
sub.render_levels = 1
bpy.context.view_layer.update()
evaluated = control.evaluated_get(bpy.context.evaluated_depsgraph_get())
surface = bpy.data.meshes.new_from_object(evaluated)
body = bpy.data.objects.new("连通木质表面", surface)
bpy.context.collection.objects.link(body)
control.hide_render = True
control.hide_set(True)
for face in surface.polygons:
    face.use_smooth = True
rest = [v.co.copy() for v in surface.vertices]
rest_nodes = [Vector(p) for p in nodes]

def nearest(p, a, b):
    tangent = b - a
    t = max(0.0, min(1.0, (p-a).dot(tangent) / tangent.length_squared))
    center = a.lerp(b, t)
    return t, center, (p-center).length_squared

# 从成熟拓扑绑定连续空间权重；所有树龄共用顶点、面和UV，不按树龄重建网格。
bindings = []
charts = []
for p in rest:
    choices = []
    for index, (a, b) in enumerate(edges):
        t, center, distance = nearest(p, rest_nodes[a], rest_nodes[b])
        choices.append((distance, index, t, center))
    choices.sort(key=lambda item: item[0])
    weights = [1 / (item[0] + .02)**2 for item in choices[:3]]
    total = sum(weights)
    bindings.append([(item[1], item[2], p-item[3], weight/total)
                     for item, weight in zip(choices[:3], weights)])
    _, index, t, center = choices[0]
    a, b = edges[index]
    tangent = (rest_nodes[b]-rest_nodes[a]).normalized()
    x = tangent.cross(Vector((0, 1, 0))).normalized()
    y = tangent.cross(x).normalized()
    offset = p-center
    charts.append((math.atan2(offset.dot(y), offset.dot(x))/(2*math.pi),
                   (rest_nodes[a].z + (rest_nodes[b]-rest_nodes[a]).length*t)*.75))
uv = surface.uv_layers.new(name="沿枝长UV")
for face in surface.polygons:
    values = [charts[surface.loops[i].vertex_index] for i in face.loop_indices]
    seam = max(v[0] for v in values)-min(v[0] for v in values) > .5
    for loop, value in zip(face.loop_indices, values):
        uv.data[loop].uv = (value[0]+(1 if seam and value[0]<0 else 0), value[1])

material = bpy.data.materials.new("统一木质与左上主光")
material.use_nodes = True
tree = material.node_tree
bsdf = tree.nodes.get("Principled BSDF")
bsdf.inputs["Roughness"].default_value = .88
image = tree.nodes.new("ShaderNodeTexImage")
image.image = bpy.data.images.load(str(ROOT / "assets/tree_scene/illustrated/bark_detail.png"))
tree.links.new(image.outputs["Color"], bsdf.inputs["Base Color"])
bump = tree.nodes.new("ShaderNodeBump")
bump.inputs["Strength"].default_value = .28
bump.inputs["Distance"].default_value = .045
tree.links.new(image.outputs["Color"], bump.inputs["Height"])
tree.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
surface.materials.append(material)
if BAKED:
    sys.path.insert(0, str(Path(__file__).parent))
    from bake_volume_material import bake_material
    bake_material(body, rest_nodes, edges, nearest, image.image, OUT)

def smooth(t):
    t = max(0, min(1, t))
    return t*t*(3-2*t)

def deform(age):
    grown = []
    for index, p in enumerate(rest_nodes):
        if index >= 11:
            grown.append(Vector((p.x*(.75+.25*age), p.y*(.75+.25*age), p.z)))
        else:
            branch = index in (5, 6, 7, 8, 9, 10)
            reach = .35+.65*smooth(age) if branch else .75+.25*age
            grown.append(Vector((p.x*reach, p.y*reach, .7+(p.z-.7)*(.65+.35*age))))
    radial = .50+.50*smooth(age)
    for vertex, binding in zip(surface.vertices, bindings):
        position = Vector()
        for edge, t, offset, weight in binding:
            a, b = edges[edge]
            rotation = (rest_nodes[b]-rest_nodes[a]).rotation_difference(grown[b]-grown[a])
            position += (grown[a].lerp(grown[b], t) + rotation @ (offset*radial))*weight
        vertex.co = position
    surface.update()

# 与平面输出分离的真实面积光照和投影，旧源模型不参与本次验证。
ground_mat = bpy.data.materials.new("接地背景")
ground_mat.diffuse_color = (.87, .81, .70, 1)
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.02))
bpy.context.object.data.materials.append(ground_mat)
bpy.ops.object.camera_add(location=(5, -9, 4.7))
camera = bpy.context.object
target = Vector((0, 0, 1.85))
camera.rotation_euler = (target-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 5.4
scene = bpy.context.scene
scene.camera = camera
for name, location, energy, size in [
    ("左上暖主光", (-4, -5, 7), 1100, 5),
    ("右侧补光", (4, -1, 4), 350, 4),
]:
    bpy.ops.object.light_add(type='AREA', location=location)
    lamp = bpy.context.object
    lamp.name = name
    lamp.data.energy = energy
    lamp.data.shape = 'DISK'
    lamp.data.size = size
    lamp.rotation_euler = (target-lamp.location).to_track_quat('-Z', 'Y').to_euler()
scene.world = bpy.data.worlds.new("柔和环境")
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.75, .72, .65, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .35
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 600
scene.render.resolution_y = 760
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'
scene.render.image_settings.file_format = 'PNG'
scene.render.fps = 12

# 连接性与封闭性检查；不能用它们代替形变和材质的实际视觉审查。
adjacency = [set() for _ in rest]
usage = {}
for face in surface.polygons:
    vertices = list(face.vertices)
    for a, b in zip(vertices, vertices[1:]+vertices[:1]):
        adjacency[a].add(b)
        adjacency[b].add(a)
        edge = tuple(sorted((a, b)))
        usage[edge] = usage.get(edge, 0)+1
seen = {0}
queue = [0]
while queue:
    for other in adjacency[queue.pop()]:
        if other not in seen:
            seen.add(other)
            queue.append(other)
components = []
remaining = set(range(len(rest)))
while remaining:
    first = next(iter(remaining))
    group = {first}
    queue = [first]
    while queue:
        for other in adjacency[queue.pop()]:
            if other not in group:
                group.add(other)
                queue.append(other)
    remaining -= group
    components.append({"vertices": len(group),
        "min": [min(rest[i][axis] for i in group) for axis in range(3)],
        "max": [max(rest[i][axis] for i in group) for axis in range(3)]})
report = {
    "script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "vertices": len(rest), "polygons": len(surface.polygons),
    "connected": len(seen) == len(rest),
    "non_manifold_edges": sum(count != 2 for count in usage.values()),
    "components": components,
    "uv": "成熟拓扑固定UV，生长随顶点；分叉图表接缝仍需视觉检查",
    "baked_material": BAKED,
    "deformation": "同一连通网格空间权重形变，非阶段整图、非整体缩放",
    "production_integrated": False,
}
if BAKED:
    report['material_script_sha256'] = hashlib.sha256(
        (Path(__file__).parent / 'bake_volume_material.py').read_bytes()).hexdigest()
    report['uv'] = '连续沿枝投影混合烘焙至固定2048图集；未凭烘焙完成宣称视觉通过'
if not report['connected'] or report['non_manifold_edges']:
    raise RuntimeError(json.dumps(report))
for name, age in [("young", 0), ("middle", .5), ("mature", 1)]:
    deform(age)
    scene.render.filepath = str(OUT / f"{name}.png")
    bpy.ops.render.render(write_still=True)
deform(1)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "independent-volume-proof.blend"))
def animate(scene):
    deform((scene.frame_current-1)/35)
bpy.app.handlers.frame_change_pre.append(animate)
scene.frame_start = 1
scene.frame_end = 36
scene.render.image_settings.file_format = 'FFMPEG'
scene.render.ffmpeg.format = 'MPEG4'
scene.render.ffmpeg.codec = 'H264'
scene.render.filepath = str(OUT / "deformation.mp4")
bpy.ops.render.render(animation=True)
(OUT / "result.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
