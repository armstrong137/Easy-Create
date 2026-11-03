"""光滑幼干及首个子枝的局部发育验证；共享母干边界，不接入正式应用。"""
from array import array
import hashlib
import json
import math
import shutil
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'build/qa/branch-development-proof'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
ROWS,COLS,BRANCH_ROWS=64,8,24
FIRST,LAST=20,28
ages=[0,.18,.5,1]
# 幼芽阶段保持短芽，随后沿同一真实母干边界伸出；干长、芽长和粗度独立。
parameters=[(1.8,.052,.045,.025),(2.2,.07,.065,.035),
            (4.3,.19,1.15,.24),(6.6,.38,2.7,.48)]
poses=[]
for height,radius,length,opening in parameters:
    junction=height*.46
    z_levels=[]
    for row in range(ROWS+1):
        if row<=FIRST:z=(junction-opening/2)*row/FIRST
        elif row<=LAST:z=junction-opening/2+opening*(row-FIRST)/(LAST-FIRST)
        else:z=junction+opening/2+(height-junction-opening/2)*(row-LAST)/(ROWS-LAST)
        z_levels.append(z)
    positions=[]
    for row,z in enumerate(z_levels):
        t=z/height
        center=radius*(.30*math.sin(t*math.pi*1.4)-.12*t)
        width=radius*(1-.78*t**1.3)
        for column in range(COLS+1):
            u=column/COLS*2-1
            positions.append([center+width*u,-width*math.sqrt(max(0,1-u*u)),z])
    base_ids=[row*(COLS+1)+COLS for row in range(FIRST,LAST+1)]
    base=[sum(positions[i][k] for i in base_ids)/len(base_ids) for k in range(3)]
    for row in range(1,BRANCH_ROWS+1):
        t=row/BRANCH_ROWS
        # 先横向离开母干，再自然上扬，半径随枝长逐渐收尖。
        reach=.10*t+.90*t*t
        x=base[0]+length*reach
        z=base[2]+length*.5*t*t*t
        slope=t*t
        norm=math.sqrt(1+slope*slope)
        nx,nz=-slope/norm,1/norm
        width=opening*.5*(1-.97*t)
        blend=min(1,t*5);blend=blend*blend*(3-2*blend)
        for column in range(COLS+1):
            u=column/COLS*2-1
            # 基圈的实际曲率在最初几圈连续退出，避免用独立封口叠放接头。
            initial=positions[base_ids[column]]
            initial_x=initial[0]-base[0]
            positions.append([x+nx*width*u+initial_x*(1-blend),
                -width*math.sqrt(max(0,1-u*u)),z+nz*width*u])
    poses.append(positions)

vertex_count=len(poses[0])
faces=[]
for row in range(ROWS):
    for col in range(COLS):
        a=row*(COLS+1)+col
        faces.extend([(a,a+1,a+COLS+2),(a,a+COLS+2,a+COLS+1)])
branch_start=(ROWS+1)*(COLS+1)
base_ids=[row*(COLS+1)+COLS for row in range(FIRST,LAST+1)]
for row in range(BRANCH_ROWS):
    previous=base_ids if row==0 else list(range(branch_start+(row-1)*(COLS+1),branch_start+row*(COLS+1)))
    current=list(range(branch_start+row*(COLS+1),branch_start+(row+1)*(COLS+1)))
    for col in range(COLS):
        # 朝向与母干一致，首排直接复用母体边界的全部九个顶点。
        faces.extend([(previous[col],current[col],current[col+1]),
                      (previous[col],current[col+1],previous[col+1])])

normals=[]
uv=[]
child_uv={base_ids[column]:[column/COLS*.5,parameters[-1][0]*.46*.3] for column in range(COLS+1)}
for row in range(ROWS+1):
    for column in range(COLS+1):
        u=column/COLS*2-1
        normals.append([u,-math.sqrt(max(0,1-u*u)),0])
        uv.append([column/COLS*.5,poses[-1][row*(COLS+1)+column][2]*.3])
for row in range(1,BRANCH_ROWS+1):
    t=row/BRANCH_ROWS;slope=t*t;norm=math.sqrt(1+slope*slope)
    blend=min(1,t*5);blend=blend*blend*(3-2*blend)
    for column in range(COLS+1):
        u=column/COLS*2-1
        normals.append([(1-blend)+blend*(-slope/norm*u),
            -math.sqrt(max(0,1-u*u))*blend,blend*u/norm])
        # 几何边界共点，沿枝UV允许在接头分缝；不把UV旋转挤压成横向条带。
        coordinate=[column/COLS*.5,parameters[-1][0]*.46*.3+parameters[-1][2]*(.10*t+.90*t*t)*.3]
        child_uv[branch_start+(row-1)*(COLS+1)+column]=coordinate
        uv.append(coordinate)

payload=array('f');sections={}
def section(name,values):
    start=len(payload);payload.extend(values)
    sections[name]={'offset':start*4,'length':len(payload)-start}
section('normals',(v for p in normals for v in p))
section('corners',(v for number,face in enumerate(faces) for i in face
    for v in [i,*(child_uv[i] if number>=ROWS*COLS*2 else uv[i])]))
for index,pose in enumerate(poses):section(f'positions{index}',(v for p in pose for v in p))
frames=[]
for age,pose in zip(ages,poses):
    connection=[sum(pose[i][k] for i in base_ids)/len(base_ids) for k in range(3)]
    tip=pose[branch_start+(BRANCH_ROWS-1)*(COLS+1)+COLS//2]
    frames.append({'age':age,'nodes':[[0,0,0],pose[ROWS*(COLS+1)+COLS//2],connection,tip],'radial':[1,1]})
metadata={'format':'共享边界局部分枝发育-v1','vertexCount':vertex_count,'triangleCount':len(faces),
    'sections':sections,'byteLength':len(payload)*4,'nodes':frames[-1]['nodes'],'edges':[[0,1],[2,3]],
    'poseFrames':frames,'vertexPoseSections':[f'positions{i}' for i in range(len(poses))],
    'samples':[{'age':age,'vertices':[{'index':i,'position':p} for i,p in enumerate(pose)]} for age,pose in zip(ages,poses)],
    'camera':{'target':[1,0,3.2],'right':[1,0,0],'up':[0,0,1],'back':[0,-1,0],'scale':8.2},
    'repeatTexture':True,'textureStyles':['wood'],'juvenileContrast':.025,'postTextureLighting':True,
    'groundShadow':False,'nearOffset':[.1,-.05],'nearSpan':[3.4,2.7],
    'scope':'仅光滑幼干、真实共享边界及首个子枝发育；没有根冠木牌，不是完整树苗或A2样件'}
(OUT/'mesh.bin').write_bytes(payload.tobytes())
(OUT/'mesh.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
source=ROOT/'assets/source/magic_tree/textures_source/pbr/bark_old_basecolor.png'
shutil.copyfile(source,OUT/'baked-bark.png')
report={'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
    'sourceImages':[{'path':str(source.relative_to(ROOT)),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}],
    'mesh_export':{'vertices':vertex_count,'triangles':len(faces),'bytes':len(payload)*4,'referenceSamples':vertex_count*len(poses)},
    'sharedBoundary':base_ids,'branchStart':branch_start,'ages':ages,'parameters':parameters,
    'uvSeam':'母子沿枝UV在共享几何边界分开，接头材质仍需美术验证',
    'production_integrated':False,'visualAcceptance':'局部方法待实际浏览器，不计完整候选轮次'}
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
mesh=bpy.data.meshes.new('母干共享边界与发育枝条');mesh.from_pydata(poses[-1],[],faces);mesh.update()
obj=bpy.data.objects.new('局部分枝发育控制网格',mesh);bpy.context.collection.objects.link(obj)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable-branch.blend'))
print(json.dumps(report['mesh_export']))
