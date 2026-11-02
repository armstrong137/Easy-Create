"""一体根颈与主肩枝源资产的连续骨架整树候选；不播放整树阶段图。"""
import hashlib
import json
import shutil
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector, Quaternion

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'build/qa/continuous-core-proof'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
source_dir=ROOT/'assets/source/magic_tree/textures_source'
paths=[source_dir/name for name in ['continuous_wood_core_v1.png','canopy_boughs_v1.png',
    'illustrated_frame_left_v1.png','illustrated_components_v1.png']]
images=[bpy.data.images.load(str(path)) for path in paths]
analysis=json.loads((ROOT/'build/qa/canopy-boughs-analysis/components.json').read_text(encoding='utf-8'))
if hashlib.sha256(paths[1].read_bytes()).hexdigest()!=analysis['sha256']:
    raise RuntimeError('冠层标签过期，请重新运行inspect-illustrated-atlas.mjs --canopy-boughs')
labels=np.frombuffer((ROOT/'build/qa/canopy-boughs-analysis/labels.bin').read_bytes(),dtype='<u4').reshape(analysis['height'],analysis['width'])
masks=[]
for image in images:
    pixels=np.empty(image.size[0]*image.size[1]*4,dtype=np.float32)
    image.pixels.foreach_get(pixels)
    masks.append(pixels.reshape(image.size[1],image.size[0],4)[::-1,:,3]>.5)

# 木体源图只映射一次，根颈、主干和五肩枝不再分层搭接。
def core_point(pixel):
    x,y=pixel
    z=float(np.interp(y,[0,120,450,730,1000,1370,1445],[7.5,6.8,4.7,2.8,1.5,0,-.25]))
    return Vector(((x-548)*.0067,0,z))

core_pixels=[(548,1370),(548,1090),(548,900),(548,730),(556,463),(550,290),(548,122),
    (350,665),(165,623),(90,530),(773,663),(949,579),(1010,512),
    (437,423),(311,351),(263,235),(709,370),(827,275),(888,175),
    (420,1190),(230,1300),(72,1325),(705,1210),(881,1315),(1000,1325)]
nodes=[core_point(p) for p in core_pixels]
edges=[(0,1),(1,2),(2,3),(3,4),(4,5),(5,6),
    (3,7),(7,8),(8,9),(3,10),(10,11),(11,12),
    (4,13),(13,14),(14,15),(4,16),(16,17),(17,18),
    (1,19),(19,20),(20,21),(1,22),(22,23),(23,24)]
frames=[]
for age in [0,.5,1]:
    if age==1:
        frames.append({'age':age,'nodes':[list(p) for p in nodes],'radial':[1]*len(edges)})
        continue
    stem_heights=[0,.20,.55,.95,1.35,1.75,2.08] if age==0 else [0,.65,1.0,1.7,2.8,3.9,4.6]
    posed=[Vector((nodes[i].x*(.12 if age==0 else .6),0,z)) for i,z in enumerate(stem_heights)]
    reach=.012 if age==0 else .55
    for i in range(7,19):
        parent=next(a for a,b in edges if b==i)
        posed.append(posed[parent]+(nodes[i]-nodes[parent])*reach)
    for i in range(19,25):
        # 根脚固定于接地附近，独立增粗，而非随整棵成年树缩放。
        posed.append(Vector((nodes[i].x*(.12 if age==0 else .55),0,nodes[i].z*(.16 if age==0 else .6))))
    radial=[(.075 if age==0 else .5) if e<6 else (.012 if age==0 else .5) if e<18 else (.12 if age==0 else .55) for e in range(len(edges))]
    frames.append({'age':age,'nodes':[list(p) for p in posed],'radial':radial})

vertices,owners,faces,uvs,materials=[],[],[],[],[]
parts,plaques=[],[]

def patch(name,material,mask,point,edge_ids,cols,rows):
    yy,xx=np.where(mask)
    x0,y0,x1,y1=max(0,int(xx.min())-3),max(0,int(yy.min())-3),min(mask.shape[1]-1,int(xx.max())+3),min(mask.shape[0]-1,int(yy.max())+3)
    start=len(vertices);piece=len(parts)
    for row in range(rows+1):
        for col in range(cols+1):
            p=point(x0+(x1-x0)*col/cols,y0+(y1-y0)*row/rows)
            p.y=-.003*piece
            vertices.append(tuple(p));owners.append(piece)
    iw,ih=images[material].size
    for row in range(rows):
        for col in range(cols):
            xa=int(x0+(x1-x0)*col/cols);xb=int(x0+(x1-x0)*(col+1)/cols)+1
            ya=int(y0+(y1-y0)*row/rows);yb=int(y0+(y1-y0)*(row+1)/rows)+1
            if not mask[ya:yb,xa:xb].any(): continue
            a=start+row*(cols+1)+col
            face=[a,a+cols+1,a+cols+2,a+1]
            faces.append(face);materials.append(material)
            uvs.append([((x0+(x1-x0)*((i-start)%(cols+1))/cols)/iw,
                1-(y0+(y1-y0)*((i-start)//(cols+1))/rows)/ih) for i in face])
    parts.append({'name':name,'edges':edge_ids,'material':material})

patch('连续根颈主干五肩枝',0,masks[0],lambda x,y:core_point((x,y)),list(range(len(edges))),48,64)

def append_piece(name,material,mask,pixels,links,parent,scale,angle=0,early=False,paper=None):
    base=Vector(pixels[0]);rotation=Quaternion((0,1,0),angle)
    local=[rotation@Vector(((x-base.x)*scale,0,(base.y-y)*scale)) for x,y in pixels]
    origin=nodes[parent];ids=[parent]
    for p in local[1:]:
        ids.append(len(nodes));nodes.append(origin+p)
        for stage,frame in enumerate(frames):
            growth=(.8,.95,1)[stage] if early else (.001,.55,1)[stage]
            frame['nodes'].append(list(Vector(frame['nodes'][parent])+p*growth))
    edge_ids=[]
    for a,b in links:
        edge_ids.append(len(edges));edges.append((ids[a],ids[b]))
        for stage,frame in enumerate(frames): frame['radial'].append((.8,.95,1)[stage] if early else (.001,.55,1)[stage])
    patch(name,material,mask,lambda x,y:origin+rotation@Vector(((x-base.x)*scale,0,(base.y-y)*scale)),edge_ids,12,12)
    if paper:
        plaques.append({'corners':[ids[i] for i in paper],'title':'第九章' if material==2 else '第一节',
            'birth':.18,'duration':.46,'unroll':True})

# 冠层按几条主肩枝分层横展，连接点位于当前连续木体内，不重复叠加通用Y分叉。
fans={1:[(585,560),(430,470),(255,320),(110,285)],
      2:[(688,570),(850,460),(1000,320),(1160,285)],
      3:[(375,1120),(380,990),(350,860),(160,950),(600,950)],
      4:[(987,1120),(990,1020),(1100,825),(865,935)]}
placements=[(1,8,.0054,-.06),(2,11,.0054,.06),(1,14,.0052,-.05),(2,17,.0052,.05),
    (3,5,.0053,0),(1,13,.0043,-.20),(2,16,.0043,.16),
    (3,4,.0045,-.10),(1,7,.0038,-.15),(2,10,.0038,.15)]
for i,(component,parent,scale,angle) in enumerate(placements):
    points=fans[component]
    links=[(0,1),(1,2),(2,3)] if component<3 else [(0,1),(1,2),(1,3),(1,4)]
    append_piece(f'横展冠层{i}',1,labels==component,points,links,parent,scale,angle)
for i,(parent,angle,scale) in enumerate([(6,0,.0028),(4,-.6,.0018)]):
    append_piece(f'早生芽枝{i}',1,labels==4,fans[4],[(0,1),(1,2),(1,3)],parent,scale,angle,True)

append_piece('左章牌',2,masks[2],[(1160,1070),(820,1030),(540,940),(248,213),(552,213),(552,902),(248,902)],
    [(0,1),(1,2),(0,3),(0,4),(0,5),(0,6)],3,.0022,paper=[3,4,5,6])
right_mask=masks[3].copy();right_mask[:500,:]=False;right_mask[:,:1030]=False
append_piece('右节牌',3,right_mask,[(1070,910),(1190,920),(1250,900),(1286,599),(1419,599),(1419,896),(1286,896)],
    [(0,1),(1,2),(0,3),(0,4),(0,5),(0,6)],3,.0045,paper=[3,4,5,6])

used=sorted({i for face in faces for i in face});remap={i:j for j,i in enumerate(used)}
mesh=bpy.data.meshes.new('连续木体与横展冠层网格')
mesh.from_pydata([vertices[i] for i in used],[],[[remap[i] for i in face] for face in faces]);mesh.update()
layer=mesh.uv_layers.new(name='固定原图UV')
for polygon,values in zip(mesh.polygons,uvs):
    for loop,value in zip(polygon.loop_indices,values): layer.data[loop].uv=value
obj=bpy.data.objects.new('连续木体候选',mesh);bpy.context.collection.objects.link(obj)
rest=[v.co.copy() for v in mesh.vertices];bindings=[]
for p,old in zip(rest,used):
    candidates=[]
    for edge in parts[owners[old]]['edges']:
        a,b=edges[edge];d=nodes[b]-nodes[a]
        t=max(0,min(1,(p-nodes[a]).dot(d)/d.length_squared));offset=p-nodes[a].lerp(nodes[b],t)
        candidates.append((offset.length_squared,edge,t,offset))
    candidates.sort(key=lambda v:v[0]);chosen=(candidates*3)[:3]
    weights=[1/(v[0]+.002)**4 for v in chosen];total=sum(weights)
    bindings.append([(edge,t,offset,weight/total) for (_,edge,t,offset),weight in zip(chosen,weights)])

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

lo=[min(p[i] for p in rest) for i in range(3)];hi=[max(p[i] for p in rest) for i in range(3)]
target=Vector(((lo[0]+hi[0])/2,0,(lo[2]+hi[2])/2))
bpy.ops.object.camera_add(location=target+Vector((0,-20,0)));camera=bpy.context.object
camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO';camera.data.ortho_scale=max((hi[2]-lo[2])*1.16,(hi[0]-lo[0])*760/600*1.15)
mesh.calc_loop_triangles()
sys.path.insert(0,str(Path(__file__).parent));from export_volume_mesh import export_mesh
exported=export_mesh(mesh,nodes,edges,bindings,camera,target,OUT,deform,{
    'poseFrames':frames,'unlitTexture':True,'triangleTextures':[materials[t.polygon_index] for t in mesh.loop_triangles],
    'extraTextures':['canopy.png','frame-left.png','frame-right-atlas.png'],
    'textureStyles':['wood','leaf','wood','wood'],'foliageParts':12,'plaques':plaques,'rootWidth':[.12,.55,1],
    'nearOffset':[target.x,-target.z+2.8],'scope':'连续木体与横展冠层第一套完整候选，尚未验收'})
for source,name in zip(paths,['baked-bark.png','canopy.png','frame-left.png','frame-right-atlas.png']):
    shutil.copyfile(source,OUT/name)
report={'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'mesh_export':exported,
    'parts':parts,'foliageParts':12,'plaques':2,'sourceImages':[{'path':str(p.relative_to(ROOT)),
        'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths],
    'continuousCore':{'nodes':len(core_pixels),'edges':24,'separateRootOverlay':False},
    'production_integrated':False,'visualAcceptance':'第一套完整候选，待实际四图与短片审查'}
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
deform(1);bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable-candidate.blend'))
print(json.dumps({'mesh_export':exported,'parts':len(parts),'output':str(OUT)},ensure_ascii=False))
