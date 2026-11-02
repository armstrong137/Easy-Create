"""局部插画分叉的连续骨骼网格验证；不含整树阶段图或正式业务。"""
import hashlib
import json
import shutil
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT/'build/qa/illustrated-fork-proof'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
image_path = ROOT/'assets/source/magic_tree/textures_source/fork_component_source_v1.png'
image = bpy.data.images.load(str(image_path))
width,height = image.size
panel = width/2
# 这些点对应实际局部图中的干基、叉心、干顶和两段侧枝，不按提示词的理想位置猜测。
landmarks = [(548,980),(535,520),(516,40),(280,395),(60,210)]
rest_nodes = [Vector(((x-548)/210,0,(980-y)/210)) for x,y in landmarks]
edges = [(0,1),(1,2),(1,3),(3,4)]
columns,rows = 48,64
vertices,faces = [],[]
for row in range(rows+1):
    for column in range(columns+1):
        x,y = panel*column/columns,height*row/rows
        vertices.append(((x-548)/210,0,(980-y)/210))
for row in range(rows):
    for column in range(columns):
        a = row*(columns+1)+column
        faces.append((a,a+columns+1,a+columns+2,a+1))
mesh = bpy.data.meshes.new('局部分叉插画网格')
mesh.from_pydata(vertices,[],faces)
mesh.update()
uv = mesh.uv_layers.new(name='原始透明局部材质')
for polygon in mesh.polygons:
    for loop in polygon.loop_indices:
        index = mesh.loops[loop].vertex_index
        row,column = divmod(index,columns+1)
        uv.data[loop].uv = (column/columns*.5,1-row/rows)
body = bpy.data.objects.new('局部分叉连续形变',mesh)
bpy.context.collection.objects.link(body)
rest = [vertex.co.copy() for vertex in mesh.vertices]
bindings = []
for p in rest:
    choices = []
    for edge,(a,b) in enumerate(edges):
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

target = Vector((-.75,0,2.2))
bpy.ops.object.camera_add(location=(-.75,-20,2.2))
camera = bpy.context.object
camera.rotation_euler = (target-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 5.8
sys.path.insert(0,str(Path(__file__).parent))
from export_volume_mesh import export_mesh
exported = export_mesh(mesh,rest_nodes,edges,bindings,camera,target,OUT,deform,
    {"poseFrames":frames,"unlitTexture":True,"groundShadow":False,
     "scope":"单个局部插画Y分叉骨骼网格，不是整树，图中无根或叶冠"})
shutil.copyfile(image_path,OUT/'baked-bark.png')
report = {"script_sha256":hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    "mesh_export":exported,"source_image_sha256":hashlib.sha256(image_path.read_bytes()).hexdigest(),
    "image_size":[width,height],"used_panel":"左半局部分叉",
    "production_integrated":False,"visualAcceptance":"待实际形变和透明边缘检查；不代表整树方法通过"}
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
