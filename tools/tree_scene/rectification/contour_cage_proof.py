"""横截面控制笼的局部木体形变验证；不含完整树冠、木牌或正式业务。"""
from array import array
import hashlib
import json
import shutil
from pathlib import Path
import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'build/qa/contour-cage-proof'
OUT.mkdir(parents=True,exist_ok=True)
source=ROOT/'assets/source/magic_tree/textures_source/continuous_wood_core_v1.png'
bpy.ops.wm.read_factory_settings(use_empty=True)
image=bpy.data.images.load(str(source));width,height=image.size
pixels=np.empty(width*height*4,dtype=np.float32);image.pixels.foreach_get(pixels)
mask=pixels.reshape(height,width,4)[::-1,:,3]>.5
yy,xx=np.where(mask)
x0,x1=max(0,int(xx.min())-3),min(width-1,int(xx.max())+3)
y0,y1=max(0,int(yy.min())-3),min(height-1,int(yy.max())+3)
columns,rows=48,64
source_points=[(x0+(x1-x0)*c/columns,y0+(y1-y0)*r/rows)
    for r in range(rows+1) for c in range(columns+1)]
quads=[]
for r in range(rows):
    for c in range(columns):
        xa=int(x0+(x1-x0)*c/columns);xb=int(x0+(x1-x0)*(c+1)/columns)+1
        ya=int(y0+(y1-y0)*r/rows);yb=int(y0+(y1-y0)*(r+1)/rows)+1
        if mask[ya:yb,xa:xb].any():
            a=r*(columns+1)+c;quads.append((a,a+columns+1,a+columns+2,a+1))
used=sorted({i for quad in quads for i in quad});remap={old:i for i,old in enumerate(used)}
points=[source_points[i] for i in used]

# 每条横截面左右有序，纵向高度严格有序；枝肩外侧和主干内侧独立伸展。
levels=[0,122,290,463,730,900,1090,1190,1300,1370,1445]
heights=[
    [3.1,2.55,2.1,1.65,1.0,.65,.3,.14,.05,0,-.04],
    [5.8,5.1,4.2,3.3,2.2,1.55,.9,.5,.14,0,-.12],
    [(1370-y)*.006 for y in levels],
]
radii=[65,65,75,100,125,100,135,200,420,545,545]
inner_scales=[
    [.00085,.00085,.00085,.00085,.00085,.00085,.00075,.0005,.00035,.0003,.0003],
    [.0032]*len(levels),
    [.006]*len(levels),
]
outer_scales=[.00002,.0022,.006]

def pose(stage):
    result=[]
    for x,y in points:
        distance=x-548;radius=float(np.interp(y,levels,radii))
        inside=float(np.interp(y,levels,inner_scales[stage]))
        span=min(abs(distance),radius)*inside+max(0,abs(distance)-radius)*outer_scales[stage]
        result.append([span if distance>=0 else -span,0,float(np.interp(y,levels,heights[stage]))])
    return result

poses=[pose(i) for i in range(3)]
mesh=bpy.data.meshes.new('横截面有序控制笼局部木体')
mesh.from_pydata(poses[2],[],[[remap[i] for i in quad] for quad in quads]);mesh.update()
uv=mesh.uv_layers.new(name='固定源图UV')
for polygon in mesh.polygons:
    for loop in polygon.loop_indices:
        x,y=points[mesh.loops[loop].vertex_index];uv.data[loop].uv=(x/width,1-y/height)
body=bpy.data.objects.new('局部轮廓控制验证',mesh);bpy.context.collection.objects.link(body)
mesh.calc_loop_triangles()
payload=array('f');sections={}

def section(name,values):
    start=len(payload);payload.extend(values)
    sections[name]={'offset':start*4,'length':len(payload)-start}

section('normals',(v for _ in points for v in [0,-1,0]))
section('corners',(v for tri in mesh.loop_triangles for loop in tri.loops
    for v in [float(mesh.loops[loop].vertex_index),*uv.data[loop].uv]))
for stage in range(3):section(f'positions{stage}',(v for p in poses[stage] for v in p))
samples=[]
for age,stage in zip([0,.5,1],range(3)):
    # 覆盖全部顶点的源对照，区别于旧方案每姿态只对照三点。
    samples.append({'age':age,'vertices':[{'index':i,'position':p} for i,p in enumerate(poses[stage])]})
low=np.min(np.array(poses[2]),axis=0);high=np.max(np.array(poses[2]),axis=0)
target=[float((low[0]+high[0])/2),0,float((low[2]+high[2])/2)]
scale=max(float(high[2]-low[2])*1.16,float(high[0]-low[0])*760/600*1.15)
meta={'format':'局部截面控制笼-v1','vertexCount':len(points),'triangleCount':len(mesh.loop_triangles),
    'sections':sections,'byteLength':len(payload)*4,
    'nodes':[[0,0,0],[0,0,8]],'edges':[[0,1]],
    'poseFrames':[{'age':age,'nodes':[[0,0,0],[0,0,heights[i][0]]],'radial':[1]} for i,age in enumerate([0,.5,1])],
    'vertexPoseSections':['positions0','positions1','positions2'],'samples':samples,
    'camera':{'target':target,'right':[1,0,0],'up':[0,0,1],'back':[0,-1,0],'scale':scale},
    'unlitTexture':True,'textureStyles':['wood'],'groundShadow':True,'rootWidth':[.08,.5,1],
    'nearOffset':[target[0],-target[2]+1.9],
    'scope':'仅局部根颈/主肩枝形变，未含叶冠与木牌，不是完整树苗或A2样件'}
(OUT/'mesh.bin').write_bytes(payload.tobytes())
(OUT/'mesh.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
shutil.copyfile(source,OUT/'baked-bark.png')
report={'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'mesh_export':{'vertices':len(points),'triangles':len(mesh.loop_triangles),'bytes':len(payload)*4,
        'referenceSamples':len(points)*3},
    'control':{'sourceLevels':levels,'heights':heights,'innerRadii':radii,'innerScales':inner_scales,'outerScales':outer_scales},
    'production_integrated':False,'visualAcceptance':'局部形变待实际浏览器核对，不计完整样件轮次'}
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable-cage.blend'))
print(json.dumps(report['mesh_export']))
