"""局部插画构件组成统一骨架整树；没有完整树阶段图片。"""
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector, Quaternion

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'build/qa/illustrated-whole-proof'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
analysis=json.loads((ROOT/'build/qa/illustrated-components-analysis/components.json').read_text(encoding='utf-8'))
labels=np.frombuffer((ROOT/'build/qa/illustrated-components-analysis/labels.bin').read_bytes(),dtype='<u4').reshape(analysis['height'],analysis['width'])
sources=[ROOT/'assets/source/magic_tree/textures_source/illustrated_components_v1.png',
         ROOT/'assets/source/magic_tree/textures_source/illustrated_frame_left_v1.png']
if analysis['sha256']!=hashlib.sha256(sources[0].read_bytes()).hexdigest():
    raise RuntimeError('图集标签已过期，请重新运行inspect-illustrated-atlas.mjs')
images=[bpy.data.images.load(str(p)) for p in sources]
left_pixels=np.empty(images[1].size[0]*images[1].size[1]*4,dtype=np.float32)
images[1].pixels.foreach_get(left_pixels)
left_mask=left_pixels.reshape(images[1].size[1],images[1].size[0],4)[::-1,:,3]>.5
components={item['id']:item for item in analysis['components']}
vertices,faces,uv_faces,face_material,owners=[],[],[],[],[]
nodes,edges=[],[]
frames=[{'age':age,'nodes':[],'radial':[]} for age in [0,.5,1]]
parts,plaques=[],[]


def add(name,kind,component,points,links,scale,parent=None,align=None,angle=0,
        reach=(.001,.5,1),branch=(.001,.5,1),thickness=(.001,.5,1),material=0,paper=None):
    # 共用真实父节点，所有局部像素/骨骼都从同一接合坐标计算。
    base=Vector(points[0])
    local=[Vector(((x-base.x)*scale,0,(base.y-y)*scale)) for x,y in points]
    if parent is None:
        parent=len(nodes)
        nodes.append(Vector((0,0,.16)))
        for frame in frames: frame['nodes'].append([0,0,.16])
    rotations=[]
    for frame in frames:
        rotation=Quaternion((0,1,0),angle)
        if align is not None:
            a,b=edges[align]
            rotation=Vector((0,0,1)).rotation_difference(Vector(frame['nodes'][b])-Vector(frame['nodes'][a]))@rotation
        rotations.append(rotation)
    origin=Vector(frames[2]['nodes'][parent])
    ids=[parent]
    for i,p in enumerate(local[1:],1):
        ids.append(len(nodes))
        nodes.append(origin+rotations[2]@p)
        for stage,frame in enumerate(frames):
            anchor=Vector(frame['nodes'][parent])
            if kind=='root':
                rest_point=nodes[-1]
                x=anchor.x+(rest_point.x-origin.x)*thickness[stage]
                z=rest_point.z*thickness[stage] if i>=2 else anchor.z*(rest_point.z/origin.z)
                posed=Vector((x,0,z))
            else:
                value=p*reach[stage]
                if kind=='fork' and i>=3:
                    middle=local[1]*reach[stage]
                    value=middle+(p-local[1])*branch[stage]
                posed=anchor+rotations[stage]@value
            frame['nodes'].append(list(posed))
    edge_ids=[]
    for a,b in links:
        edge_ids.append(len(edges));edges.append((ids[a],ids[b]))
        for stage,frame in enumerate(frames): frame['radial'].append(thickness[stage])
    piece=len(parts)
    if material==0:
        x0,y0,x1,y1=components[component]['bounds']
        mask=labels==component
    else:
        yy,xx=np.where(left_mask)
        x0,y0,x1,y1=int(xx.min()),int(yy.min()),int(xx.max()),int(yy.max())
        mask=left_mask
    x0,y0=max(0,x0-3),max(0,y0-3)
    x1,y1=min(mask.shape[1]-1,x1+3),min(mask.shape[0]-1,y1+3)
    cols,rows=(10,12) if kind=='leaf' else (28,36)
    start=len(vertices)
    for row in range(rows+1):
        for col in range(cols+1):
            x=x0+(x1-x0)*col/cols;y=y0+(y1-y0)*row/rows
            p=origin+rotations[2]@Vector(((x-base.x)*scale,0,(base.y-y)*scale))
            p.y=-.002*(piece+1) if kind!='root' else -.25
            vertices.append(tuple(p));owners.append(piece)
    iw,ih=images[material].size
    for row in range(rows):
        for col in range(cols):
            xa=int(x0+(x1-x0)*col/cols);xb=int(x0+(x1-x0)*(col+1)/cols)+1
            ya=int(y0+(y1-y0)*row/rows);yb=int(y0+(y1-y0)*(row+1)/rows)+1
            if not mask[ya:yb,xa:xb].any(): continue
            a=start+row*(cols+1)+col
            face=[a,a+cols+1,a+cols+2,a+1]
            faces.append(face);face_material.append(material)
            uv=[]
            for index in face:
                r,c=divmod(index-start,cols+1)
                uv.append(((x0+(x1-x0)*c/cols)/iw,1-(y0+(y1-y0)*r/rows)/ih))
            uv_faces.append(uv)
    parts.append({'name':name,'kind':kind,'ids':ids,'edge_ids':edge_ids,'component':component,'material':material})
    if paper:
        plaques.append({'corners':[ids[i] for i in paper],'birth':.18,'duration':.46,
                        'title':'第九章' if material else '第一节'})
    return parts[-1]


left=[(886,465),(870,250),(875,45),(720,205),(630,98)]
right=[(1140,465),(1155,250),(1145,45),(1300,205),(1460,98)]
fork_links=[(0,1),(1,2),(1,3),(3,4)]
main=add('主干左分叉','fork',1,left,fork_links,.009,reach=(.28,.63,1),
         branch=(.004,.45,1),thickness=(.16,.55,1))
low=add('低位右分叉','fork',2,right,fork_links,.009*.72,parent=main['ids'][1],
        reach=(.001,.55,1),branch=(.001,.45,1),thickness=(.001,.5,1))
upper=add('中轴右分叉','fork',2,right,fork_links,.009*.60,parent=main['ids'][2],align=main['edge_ids'][1])
top=add('冠顶左分叉','fork',1,left,fork_links,.009*.36,parent=upper['ids'][2],align=upper['edge_ids'][1])
wing_l=add('左冠支撑','fork',2,right,fork_links,.009*.47,parent=main['ids'][4],align=main['edge_ids'][3])
wing_r=add('右冠支撑','fork',1,left,fork_links,.009*.43,parent=low['ids'][4],align=low['edge_ids'][3])
left_high=add('左冠上拱','fork',2,right,fork_links,.009*.28,parent=wing_l['ids'][4],align=wing_l['edge_ids'][3])
right_high=add('右冠上拱','fork',1,left,fork_links,.009*.25,parent=wing_r['ids'][4],align=wing_r['edge_ids'][3])
forks=[main,low,upper,top,wing_l,wing_r,left_high,right_high]
tips=[]
tip_points=[(170,965),(285,745),(375,610),(430,535),(490,560)]
for index,part in enumerate(forks):
    for local_node,edge_index in [(2,1),(4,3)]:
        tips.append(add(f'枝梢{index}-{local_node}','tip',5,tip_points,fork_links,.009*(.22 if index<4 else .16),
                        parent=part['ids'][local_node],align=part['edge_ids'][edge_index]))
# 根颈覆盖主干基部，与母干中段骨点共用；根脚向固定地面增粗，避免整张成年树缩放。
root_scale=nodes[main['ids'][1]].z/(484-100)
add('连通根颈','root',3,[(320,100),(320,280),(100,425),(570,425),(350,455)],
    [(0,1),(1,2),(1,3),(1,4)],root_scale,parent=main['ids'][1],
    thickness=(.18,.60,1))
leaf_points=[(790,960),(765,790),(770,570),(600,740),(940,700)]
leaf_links=[(0,1),(1,2),(1,3),(1,4)]
add('幼苗早生冠','leaf',6,leaf_points,leaf_links,.009*.20,parent=main['ids'][2],
    reach=(.65,.85,1),thickness=(.65,.85,1))
leaf_count=1
for index,part in enumerate(tips):
    for local_node in [2,3,4]:
        scale=.009*(.20+.035*math.sin(index*1.7+local_node))
        add(f'叶簇{index}-{local_node}','leaf',6,leaf_points,leaf_links,scale,parent=part['ids'][local_node],
            angle=.38*math.sin(index*2.1+local_node),reach=(.001,.45,1),thickness=(.001,.45,1))
        leaf_count+=1
# 纸面锚点预留内缩量，交由现有画笔用相同当前骨点绘制。
add('左侧章牌','frame',0,[(1160,1070),(820,1030),(540,940),
    (248,213),(552,213),(552,902),(248,902)],[(0,1),(1,2),(0,3),(0,4),(0,5),(0,6)],
    .0022,parent=main['ids'][1],reach=(.001,.55,1),thickness=(.001,.55,1),material=1,paper=[3,4,5,6])
add('右侧节牌','frame',4,[(1070,910),(1190,920),(1250,900),
    (1286,599),(1419,599),(1419,896),(1286,896)],[(0,1),(1,2),(0,3),(0,4),(0,5),(0,6)],
    .0045,parent=main['ids'][1],reach=(.001,.55,1),thickness=(.001,.55,1),paper=[3,4,5,6])

used=sorted({i for polygon in faces for i in polygon})
remap={i:j for j,i in enumerate(used)}
mesh=bpy.data.meshes.new('统一局部插画整树网格')
mesh.from_pydata([vertices[i] for i in used],[],[[remap[i] for i in p] for p in faces]);mesh.update()
uv=mesh.uv_layers.new(name='构件原图UV')
for polygon,values in zip(mesh.polygons,uv_faces):
    for loop,value in zip(polygon.loop_indices,values): uv.data[loop].uv=value
body=bpy.data.objects.new('统一骨架整树候选',mesh);bpy.context.collection.objects.link(body)
rest=[vertex.co.copy() for vertex in mesh.vertices]

def binding_for(p,edge_ids):
    choices=[]
    for edge in edge_ids:
        a,b=edges[edge];d=nodes[b]-nodes[a]
        t=max(0,min(1,(p-nodes[a]).dot(d)/d.length_squared));center=nodes[a].lerp(nodes[b],t)
        choices.append(((p-center).length_squared,edge,t,p-center))
    choices.sort(key=lambda item:item[0])
    selected=(choices*3)[:3] if len(choices)<3 else choices[:3]
    weights=[1/(v[0]+.005)**3 for v in selected];total=sum(weights)
    return [(edge,t,offset,w/total) for (_,edge,t,offset),w in zip(selected,weights)]

bindings=[binding_for(p,parts[owners[old]]['edge_ids']) for p,old in zip(rest,used)]

def deform(age):
    a,b=(frames[0],frames[1]) if age<=.5 else (frames[1],frames[2])
    t=(age-a['age'])/(b['age']-a['age']);t=t*t*(3-2*t)
    grown=[Vector(x).lerp(Vector(y),t) for x,y in zip(a['nodes'],b['nodes'])]
    radial=[x+(y-x)*t for x,y in zip(a['radial'],b['radial'])]
    for vertex,binding in zip(mesh.vertices,bindings):
        p=Vector()
        for edge,s,offset,weight in binding:
            first,last=edges[edge]
            q=(nodes[last]-nodes[first]).rotation_difference(grown[last]-grown[first])
            p+=(grown[first].lerp(grown[last],s)+q@(offset*radial[edge]))*weight
        vertex.co=p
    mesh.update()

target=Vector((0,0,4.0));bpy.ops.object.camera_add(location=(0,-20,4.0));camera=bpy.context.object
camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=10.8
mesh.calc_loop_triangles()
textures=[face_material[tri.polygon_index] for tri in mesh.loop_triangles]
sys.path.insert(0,str(Path(__file__).parent));from export_volume_mesh import export_mesh
exported=export_mesh(mesh,nodes,edges,bindings,camera,target,OUT,deform,
    {'poseFrames':frames,'unlitTexture':True,'triangleTextures':textures,
     'extraTextures':['frame-left.png'],'foliageParts':leaf_count,'plaques':plaques,
     'nearOffset':[0,-1.4],'scope':'局部插画统一整树首套候选，未集成'})
shutil.copyfile(sources[0],OUT/'baked-bark.png');shutil.copyfile(sources[1],OUT/'frame-left.png')
report={'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'mesh_export':exported,
        'parts':len(parts),'foliageParts':leaf_count,'plaques':len(plaques),
        'image_sha256':[hashlib.sha256(p.read_bytes()).hexdigest() for p in sources],
        'source_regions':analysis['components'],'production_integrated':False,
        'visualAcceptance':'首套统一候选，待实际四图与短片审查'}
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
