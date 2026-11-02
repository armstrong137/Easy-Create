"""局部插画分叉的连续骨骼网格验证；不含整树阶段图或正式业务。"""
import hashlib
import json
import shutil
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
LAP = '--lap' in sys.argv
PAIR = '--pair' in sys.argv or LAP
OUT = ROOT/('build/qa/illustrated-pair-lap-proof' if LAP else 'build/qa/illustrated-pair-proof' if PAIR else 'build/qa/illustrated-fork-proof')
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
image_path = ROOT/('assets/source/magic_tree/textures_source/fork_component_lap_v2.png' if LAP else
                   'assets/source/magic_tree/textures_source/fork_component_source_v1.png')
image = bpy.data.images.load(str(image_path))
width,height = image.size
panel = width/2
# 这些点对应实际局部图中的干基、叉心、干顶和两段侧枝，不按提示词的理想位置猜测。
landmarks = [(548,980),(535,520),(516,40),(280,395),(60,210)]
rest_nodes = [Vector(((x-548)/210,0,(980-y)/210)) for x,y in landmarks]
edges = [(0,1),(1,2),(1,3),(3,4)]
child_scale = .57
child_base = Vector((988,900 if LAP else 966))
child_pixels = [tuple(child_base),(1000,520),(1020,40),(1255,395),(1480,210)]
child_local = [Vector(((x-child_base.x)/210,0,(child_base.y-y)/210)) for x,y in child_pixels]
rest_rotation = Vector((0,0,1)).rotation_difference(rest_nodes[2]-rest_nodes[1])
if PAIR:
    # 子段根骨直接复用父段干顶节点2；右格保持原始光向，不镜像左格。
    rest_nodes += [rest_nodes[2]+rest_rotation@(p*child_scale) for p in child_local[1:]]
    edges += [(2,5),(5,6),(5,7),(7,8)]
columns,rows = 48,64
vertices,faces = [],[]
piece_vertices = (rows+1)*(columns+1)
for piece in range(2 if PAIR else 1):
    for row in range(rows+1):
        for column in range(columns+1):
            x,y = panel*column/columns+piece*panel,height*row/rows
            if piece:
                local = Vector(((x-child_base.x)/210,0,(child_base.y-y)/210))
                p = rest_nodes[2]+rest_rotation@(local*child_scale)
                p.y = -.01
            else:
                p = Vector(((x-548)/210,0,(980-y)/210))
            vertices.append(tuple(p))
    for row in range(rows):
        for column in range(columns):
            a = piece*piece_vertices+row*(columns+1)+column
            faces.append((a,a+columns+1,a+columns+2,a+1))
mesh = bpy.data.meshes.new('局部分叉插画网格')
mesh.from_pydata(vertices,[],faces)
mesh.update()
uv = mesh.uv_layers.new(name='原始透明局部材质')
for polygon in mesh.polygons:
    for loop in polygon.loop_indices:
        index = mesh.loops[loop].vertex_index
        piece,local_index = divmod(index,piece_vertices)
        row,column = divmod(local_index,columns+1)
        uv.data[loop].uv = (piece*.5+column/columns*.5,1-row/rows)
body = bpy.data.objects.new('局部分叉连续形变',mesh)
bpy.context.collection.objects.link(body)
rest = [vertex.co.copy() for vertex in mesh.vertices]
bindings = []
for index,p in enumerate(rest):
    choices = []
    for edge,(a,b) in enumerate(edges):
        if PAIR and edge//4 != index//piece_vertices:
            continue
        d = rest_nodes[b]-rest_nodes[a]
        t = max(0,min(1,(p-rest_nodes[a]).dot(d)/d.length_squared))
        center = rest_nodes[a].lerp(rest_nodes[b],t)
        choices.append(((p-center).length_squared,edge,t,p-center))
    choices.sort(key=lambda choice:choice[0])
    weights = [1/(choice[0]+.005)**3 for choice in choices[:3]]
    total = sum(weights)
    bindings.append([(edge,t,offset,w/total) for (_,edge,t,offset),w in zip(choices[:3],weights)])
frames = [
    {"age":0,"nodes":[[0,0,0],[-.02,0,1.2],[.03,0,2.2],[-.30,0,1.5],[-.65,0,1.9]],"radial":[.60,.50,.30,.20]},
    {"age":.5,"nodes":[[0,0,0],[-.04,0,1.8],[-.06,0,3.6],[-.90,0,2.4],[-1.7,0,2.8]],"radial":[.85,.80,.60,.50]},
    {"age":1,"nodes":[list(p) for p in rest_nodes],"radial":[1,1,1,1]},
]
if PAIR:
    for frame,trunk_reach,branch_reach in zip(frames,[.5,.8,1],[.3,.65,1]):
        parent = [Vector(p) for p in frame['nodes']]
        rotation = Vector((0,0,1)).rotation_difference(parent[2]-parent[1])
        local = [Vector(),child_local[1]*trunk_reach,child_local[2]*trunk_reach]
        local += [local[1]+(child_local[3]-child_local[1])*branch_reach]
        local += [local[3]+(child_local[4]-child_local[3])*branch_reach]
        frame['nodes'] += [list(parent[2]+rotation@(p*child_scale)) for p in local[1:]]
        width_scale = frame['radial'][1]
        frame['radial'] += [width_scale,width_scale,
                           width_scale*(.6+.4*branch_reach),width_scale*(.6+.4*branch_reach)]

def deform(age):
    a,b = (frames[0],frames[1]) if age<=.5 else (frames[1],frames[2])
    t = (age-a['age'])/(b['age']-a['age'])
    t = t*t*(3-2*t)
    grown = [Vector(x).lerp(Vector(y),t) for x,y in zip(a['nodes'],b['nodes'])]
    radial = [x+(y-x)*t for x,y in zip(a['radial'],b['radial'])]
    for vertex,binding in zip(mesh.vertices,bindings):
        p = Vector()
        for edge,s,offset,weight in binding:
            first,last = edges[edge]
            rotation = (rest_nodes[last]-rest_nodes[first]).rotation_difference(grown[last]-grown[first])
            p += (grown[first].lerp(grown[last],s)+rotation@(offset*radial[edge]))*weight
        vertex.co = p
    mesh.update()

target = Vector((-.45,0,3.6) if PAIR else (-.75,0,2.2))
bpy.ops.object.camera_add(location=(target.x,-20,target.z))
camera = bpy.context.object
camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 8.6 if PAIR else 5.8
sys.path.insert(0,str(Path(__file__).parent))
from export_volume_mesh import export_mesh
extra = {"poseFrames":frames,"unlitTexture":True,"groundShadow":False,
         "scope":"两个局部插画分叉共享骨骼接合" if PAIR else "单个局部插画Y分叉骨骼网格，不是整树，图中无根或叶冠"}
if PAIR:
    extra.update({"nearOffset":[-.30,.88],"sharedDockNode":2})
    # 额外覆盖接头两侧网格点，供独立Dart在四分之一姿态对照，而非只检查共用骨点。
    probes = [row*(columns+1)+column for row in [2,3] for column in [30,32,34]]
    probes += [piece_vertices+row*(columns+1)+column for row in
               [round(child_base.y/height*rows),60] for column in [11,13,15,17]]
    probes = sorted(set(probes))
    samples = []
    for age in [0,.25,.5,.75,1]:
        deform(age)
        samples.append({"age":age,"vertices":[{"index":i,"position":list(mesh.vertices[i].co)} for i in probes]})
    deform(1)
    extra['samples'] = samples
exported = export_mesh(mesh,rest_nodes,edges,bindings,camera,target,OUT,deform,extra)
shutil.copyfile(image_path,OUT/'baked-bark.png')
report = {"script_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "mesh_export":exported,"source_image_sha256":hashlib.sha256(image_path.read_bytes()).hexdigest(),
    "image_size":[width,height],"used_panel":"左右两格，共享节点2" if PAIR else "左半局部分叉",
    "production_integrated":False,"visualAcceptance":"待实际形变和透明边缘检查；不代表整树方法通过"}
if PAIR:
    report.update({"shared_dock_node":2,"child_scale":child_scale,
                   "child_source_base":list(child_base),"dock_probe_vertices":probes,
                   "lap_material":LAP})
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
