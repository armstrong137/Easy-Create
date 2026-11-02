"""连接控制面与沿枝UV验证：不使用体积并集、自动分图或旧母版。"""
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
WHOLE = '--whole' in sys.argv
OUT = ROOT / ('build/qa/authored-whole-control' if WHOLE else 'build/qa/authored-surface-proof')
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
vertices, faces, face_uv = [], [], []
rest_nodes, edges, node_roles = [], [], []


def point(p):
    vertices.append(tuple(p))
    return len(vertices)-1


def face(indices, uv):
    faces.append(indices)
    face_uv.append(uv)


def skeleton(p, role, parent=None):
    index = len(rest_nodes)
    rest_nodes.append(Vector(p))
    node_roles.append((role, parent))
    if parent is not None:
        edges.append((parent, index))
    return index


def ring(center, radius, tangent, sides, phase=0):
    tangent = Vector(tangent).normalized()
    x = tangent.cross(Vector((0, 1, 0))).normalized()
    y = tangent.cross(x).normalized()
    return [point(Vector(center)+radius*(math.cos(phase+k*math.tau/sides)*x+
        math.sin(phase+k*math.tau/sides)*y)) for k in range(sides)]


def bridge(a, b, va, vb, width):
    for k in range(len(a)):
        following = (k+1) % len(a)
        face([a[k], a[following], b[following], b[k]],
             [(k/len(a)*width, va), ((k+1)/len(a)*width, va),
              ((k+1)/len(a)*width, vb), (k/len(a)*width, vb)])


# 母干横截面和纵向控制层均明确保留，孔口边界作为子枝的第一圈共用顶点。
centers = [Vector(p) for p in [
    (0, 0, .08), (-.03, 0, .35), (-.08, .03, .70), (-.10, .05, 1.15),
    (-.06, .04, 1.70), (.06, .02, 2.30), (.13, .06, 2.90),
    (.07, .10, 3.45), (-.08, .17, 4.00), (-.17, .20, 4.55),
    (-.13, .24, 5.15), (.04, .27, 5.80), (.14, .28, 6.45),
    (.10, .30, 7.10), (.05, .30, 7.75),
]]
radii = [.48, .62, .70, .67, .58, .52, .46, .41, .34, .29, .23, .18, .12, .065, .018]
trunk_ids = [skeleton(p, 'trunk', i-1 if i else None) for i, p in enumerate(centers)]
slots = [(1, j, 'root') for j in range(0, 24, 4)]
slots += [(5, 11, 'left'), (7, 23, 'right')]
removed = {(i+di, (j+dj) % 24) for i, j, _ in slots for di in range(2) for dj in range(2)}
trunk_rings = []
for i, (center, radius) in enumerate(zip(centers, radii)):
    # 较粗截面保留非圆对称脊线；不在简化后的密集小三角上逐点刻随机凹凸。
    ids = []
    for k in range(24):
        angle = k*math.tau/24
        relief = 1+.09*math.cos(angle*6+.28*center.z)+.045*math.sin(angle*3-.37*center.z)
        ids.append(point(center+Vector((math.cos(angle)*radius*relief,
                                        math.sin(angle)*radius*relief, 0))))
    trunk_rings.append(ids)
for i in range(len(centers)-1):
    for j in range(24):
        if (i, j) in removed:
            continue
        nxt = (j+1) % 24
        face([trunk_rings[i][j], trunk_rings[i][nxt], trunk_rings[i+1][nxt], trunk_rings[i+1][j]],
             [(j/24, centers[i].z*.16), ((j+1)/24, centers[i].z*.16),
              ((j+1)/24, centers[i+1].z*.16), (j/24, centers[i+1].z*.16)])
for ids in [trunk_rings[0][::-1], trunk_rings[-1]]:
    face(ids, [(.5+.12*math.cos(k*math.tau/24), .5+.12*math.sin(k*math.tau/24)) for k in range(24)])

for i, j, role in slots:
    # 2×2四边面开口的八点边界，下一圈与它逐点桥接，不覆盖母干表面。
    coordinates = [(i,j), (i,j+1), (i,j+2), (i+1,j+2),
                   (i+2,j+2), (i+2,j+1), (i+2,j), (i+1,j)]
    boundary = [trunk_rings[row][column % 24] for row, column in coordinates]
    center = sum((Vector(vertices[index]) for index in boundary), Vector())/8
    theta = (j+1)*math.tau/24
    direction = Vector((math.cos(theta), math.sin(theta), 0))
    if role == 'root':
        reach = [1.60, 1.38, 1.72, 1.46, 1.28, 1.55][j//4]
        path = [(direction*.88+Vector((0, 0, .53)), .27),
                (direction*(reach*.78)+Vector((.06*math.sin(j), .03*math.cos(j), .20)), .16),
                (direction*reach+Vector((.10*math.sin(j), 0, .055)), .025)]
    elif role == 'left':
        path = [(Vector((-.88, -.10, 2.98)), .34), (Vector((-1.43, -.08, 3.35)), .29),
                (Vector((-2.03, .01, 3.84)), .21), (Vector((-2.60, .14, 4.17)), .12),
                (Vector((-3.04, .20, 4.66)), .025)]
    else:
        path = [(Vector((.83, -.08, 4.06)), .29), (Vector((1.40, -.02, 4.38)), .25),
                (Vector((1.95, .10, 4.86)), .19), (Vector((2.39, .18, 5.40)), .10),
                (Vector((2.66, .25, 5.98)), .025)]
    parent = trunk_ids[i+1]
    previous, previous_center, v = boundary, center, center.z*.16
    for step, (p, radius) in enumerate(path):
        tangent = p-previous_center if step == len(path)-1 else path[step+1][0]-previous_center
        tangent.normalize()
        x = tangent.cross(Vector((0, 1, 0))).normalized()
        y = tangent.cross(x).normalized()
        radial = (Vector(vertices[previous[0]])-previous_center).normalized()
        phase = math.atan2(radial.dot(y), radial.dot(x))
        current = ring(p, radius, tangent, 8, phase)
        next_v = v+(p-previous_center).length*.16
        bridge(previous, current, v, next_v, .52 if role == 'root' else .64)
        parent = skeleton(p, role, parent)
        previous, previous_center, v = current, p, next_v
    face(previous[::-1], [(.5+.02*math.cos(k*math.tau/8), v+.02*math.sin(k*math.tau/8)) for k in range(8)])

whole = None
if WHOLE:
    sys.path.insert(0, str(Path(__file__).parent))
    from authored_whole_control import build
    whole = build()
    vertices, faces, face_uv = whole['vertices'], whole['faces'], whole['face_uv']
    rest_nodes, edges, node_roles = whole['rest_nodes'], whole['edges'], whole['node_roles']
mesh = bpy.data.meshes.new('解剖控制面网格')
# 孔口中央控制点已不属于任何面，创建网格时即排除这些未使用点。
used = sorted({index for polygon in faces for index in polygon})
remap = {index: position for position, index in enumerate(used)}
mesh.from_pydata([vertices[index] for index in used], [],
                 [[remap[index] for index in polygon] for polygon in faces])
mesh.update()
uv = mesh.uv_layers.new(name='沿枝长连续条带')
for polygon, coordinates in zip(mesh.polygons, face_uv):
    for loop, coordinate in zip(polygon.loop_indices, coordinates):
        uv.data[loop].uv = coordinate
# 统一封闭网格的面朝向；保持开口桥接关系，不进行重网格或合并小块。
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()
control = bpy.data.objects.new('可编辑根颈与分叉控制面', mesh)
bpy.context.collection.objects.link(control)
modifier = control.modifiers.new('控制面细分', 'SUBSURF')
modifier.levels = 1 if WHOLE else 2
modifier.render_levels = modifier.levels
modifier.uv_smooth = 'PRESERVE_BOUNDARIES'
bpy.context.view_layer.update()
surface = bpy.data.meshes.new_from_object(control.evaluated_get(bpy.context.evaluated_depsgraph_get()))
body = bpy.data.objects.new('控制面二维导出表面', surface)
bpy.context.collection.objects.link(body)
control.hide_render = True
control.hide_set(True)
for polygon in surface.polygons:
    polygon.use_smooth = True
rest = [vertex.co.copy() for vertex in surface.vertices]

def nearest(p, a, b):
    d = b-a
    t = max(0, min(1, (p-a).dot(d)/d.length_squared))
    center = a.lerp(b, t)
    return t, center, (p-center).length_squared


bindings = []
for p in rest:
    choices = []
    for edge, (a, b) in enumerate(edges):
        t, center, distance = nearest(p, rest_nodes[a], rest_nodes[b])
        choices.append((distance, edge, t, center))
    choices.sort(key=lambda item: item[0])
    weights = [1/(choice[0]+.01)**2 for choice in choices[:3]]
    total = sum(weights)
    bindings.append([(edge, t, p-center, weight/total)
        for (_, edge, t, center), weight in zip(choices[:3], weights)])

# 三个控制姿态在同一骨架与表面上连续插值，根、主干和子枝各自有长度/粗度变化。
pose_frames = []
for age, trunk_reach, branch_reach, root_reach, thickness in [
    (0, .24, .06, .18, .09), (.5, .66, .52, .58, .48), (1, 1, 1, 1, 1)]:
    posed = []
    for index, (role, parent) in enumerate(node_roles):
        p = rest_nodes[index]
        if role == 'trunk':
            posed.append(Vector((p.x*trunk_reach, p.y*trunk_reach, .03+(p.z-.03)*trunk_reach)))
        elif role == 'root':
            posed.append(Vector((p.x*root_reach, p.y*root_reach, p.z*root_reach)))
        else:
            posed.append(posed[parent]+(p-rest_nodes[parent])*branch_reach)
    pose_frames.append({"age": age, "nodes": [list(p) for p in posed],
        "radial": [thickness if node_roles[b][0]=='trunk' else thickness*(.45+.55*branch_reach)
                   if node_roles[b][0] in ('left', 'right', 'branch', 'twig', 'frame') else thickness for a, b in edges]})


def sample_pose(age):
    first, last = (pose_frames[0], pose_frames[1]) if age <= .5 else (pose_frames[1], pose_frames[2])
    t = (age-first['age'])/(last['age']-first['age'])
    t = t*t*(3-2*t)
    grown = [Vector(a).lerp(Vector(b), t) for a, b in zip(first['nodes'], last['nodes'])]
    radial = [a+(b-a)*t for a, b in zip(first['radial'], last['radial'])]
    return grown, radial


def deform(age):
    grown, radial = sample_pose(age)
    for vertex, binding in zip(surface.vertices, bindings):
        p = Vector()
        for edge, t, offset, weight in binding:
            a, b = edges[edge]
            rotation = (rest_nodes[b]-rest_nodes[a]).rotation_difference(grown[b]-grown[a])
            p += (grown[a].lerp(grown[b], t)+rotation @ (offset*radial[edge]))*weight
        vertex.co = p
    surface.update()


material = bpy.data.materials.new('沿枝长树皮与统一光向')
material.use_nodes = True
nodes = material.node_tree.nodes
links = material.node_tree.links
shader = nodes.get('Principled BSDF')
shader.inputs['Roughness'].default_value = .90
texture = nodes.new('ShaderNodeTexImage')
texture.image = bpy.data.images.load(str(ROOT / 'assets/source/magic_tree/textures_source/pbr/bark_old_basecolor.png'))
texture.extension = 'REPEAT'
links.new(texture.outputs['Color'], shader.inputs['Base Color'])
bump = nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = .22
bump.inputs['Distance'].default_value = .035
links.new(texture.outputs['Color'], bump.inputs['Height'])
links.new(bump.outputs['Normal'], shader.inputs['Normal'])
surface.materials.append(material)
mesh.materials.append(material)
shutil.copyfile(ROOT / 'assets/source/magic_tree/textures_source/pbr/bark_old_basecolor.png', OUT / 'baked-bark.png')

check = bmesh.new()
check.from_mesh(surface)
bad_edges = sum(not edge.is_manifold for edge in check.edges)
components, seen = [], set()
for vertex in check.verts:
    if vertex in seen:
        continue
    queue, group = [vertex], set()
    while queue:
        current = queue.pop()
        if current in group:
            continue
        group.add(current)
        queue.extend(edge.other_vert(current) for edge in current.link_edges)
    seen.update(group)
    components.append(len(group))
check.free()
if bad_edges or len(components) != 1:
    raise RuntimeError(f'控制面接头未封闭连通：{bad_edges}, {components}')

target = Vector((0, 0, 5.0) if WHOLE else (0, 0, 3.8))
bpy.ops.object.camera_add(location=(0, -20, 8.3) if WHOLE else (4.2, -16, 7.0))
camera = bpy.context.object
camera.rotation_euler = (target-camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 11.8 if WHOLE else 9.3
scene = bpy.context.scene
scene.camera = camera
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 800
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.world = bpy.data.worlds.new('柔和浅色环境')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs[0].default_value = (.83, .77, .65, 1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value = .5
scene.view_settings.view_transform = 'AgX'
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.025))
floor = bpy.context.object
floor_material = bpy.data.materials.new('暖色接地')
floor_material.diffuse_color = (.84, .77, .65, 1)
floor.data.materials.append(floor_material)
for location, energy, size in [((-5, -7, 10), 1600, 7), ((4, 2, 7), 900, 6)]:
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.object
    light.data.energy, light.data.size = energy, size
    light.rotation_euler = (target-light.location).to_track_quat('-Z', 'Y').to_euler()

sys.path.insert(0, str(Path(__file__).parent))
from export_volume_mesh import export_mesh
extra = {"poseFrames": pose_frames, "repeatTexture": True,
         "scope": "控制面整树首轮" if WHOLE else "根颈和两处母子分叉控制面验证，不是整树样件"}
if WHOLE:
    extra.update({name:whole[name] for name in ['leaves','plaques','leafAtlas']})
    shutil.copyfile(ROOT / 'assets/source/magic_tree/textures_source/leaf_matte_atlas_v2.png', OUT / 'leaf.png')
exported = export_mesh(surface, rest_nodes, edges, bindings, camera, target, OUT, deform, extra)
for name, age in [('young', 0), ('middle', .5), ('mature', 1)]:
    deform(age)
    scene.render.filepath = str(OUT / f'{name}.png')
    bpy.ops.render.render(write_still=True)
deform(1)
# 另存显示控制笼的线框证据；保留源控制面及细分修改器以便继续美术制作。
control.hide_render = False
control.hide_set(False)
control.show_wire = True
control.show_all_edges = True
control.modifiers.clear()
neutral = bpy.data.materials.new('控制面灰底')
neutral.diffuse_color = (.45, .50, .55, 1)
wire_material = bpy.data.materials.new('控制面深色边')
wire_material.diffuse_color = (.015, .02, .025, 1)
mesh.materials[0] = neutral
mesh.materials.append(wire_material)
body.hide_render = True
wire = control.modifiers.new('控制面线框证据', 'WIREFRAME')
wire.thickness = .018
wire.use_replace = False
wire.material_offset = 1
scene.render.filepath = str(OUT / 'control-cage.png')
bpy.ops.render.render(write_still=True)
control.modifiers.clear()
mesh.materials.clear()
mesh.materials.append(material)
subdivision = control.modifiers.new('控制面细分', 'SUBSURF')
subdivision.levels = 1 if WHOLE else 2
subdivision.uv_smooth = 'PRESERVE_BOUNDARIES'
control.hide_render = True
control.hide_set(True)
body.hide_render = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'authored-surface-proof.blend'))
report = {"script_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "control_vertices": len(mesh.vertices), "control_faces": len(mesh.polygons),
    "vertices": len(surface.vertices), "components": components, "non_manifold_edges": bad_edges,
    "mesh_export": exported, "uv_method": '按解剖部位手工定义条带，重复采样原1024树皮，无自动分图/烘焙',
    "production_integrated": False, "visualAcceptance": '待实图检查，仅局部方法验证，A2未完成'}
if WHOLE:
    report.update({"whole_spec_sha256":hashlib.sha256((Path(__file__).parent/'authored_whole_control.py').read_bytes()).hexdigest(),
                   "leaves":len(whole['leaves']),"plaques":len(whole['plaques']),
                   "visualAcceptance":"控制面整树首轮，待四图与短片审查，未集成"})
(OUT / 'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
