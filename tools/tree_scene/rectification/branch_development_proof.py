"""光滑幼干及首个子枝的局部发育验证；共享母干边界，不接入正式应用。"""
from array import array
import hashlib
import json
import math
import shutil
import struct
import sys
from pathlib import Path
try:
    import bpy
except ModuleNotFoundError:
    bpy=None

ROOT=Path(__file__).resolve().parents[3]
ROOT_COLLAR='--root-collar' in sys.argv
OUT=ROOT/'build/qa'/('shared-root-collar-proof' if ROOT_COLLAR else 'branch-development-proof')
OUT.mkdir(parents=True,exist_ok=True)
ROWS,COLS,BRANCH_ROWS=64,8,24
FIRST,LAST=20,28
ages=[0,.18,.5,1]
root_boundaries=[
    [row*(COLS+1)+column for row in range(COLS+1)]
    for column in (0,COLS)
] if ROOT_COLLAR else []
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
    if ROOT_COLLAR:
        for row in range(FIRST+1):
            collar=radius*1.85
            z_levels[row]=(collar*row/COLS if row<=COLS else
                collar+(junction-opening/2-collar)*(row-COLS)/(FIRST-COLS))
    positions=[]
    for row,z in enumerate(z_levels):
        t=z/height
        center=radius*(.30*math.sin(t*math.pi*1.4)-.12*t)
        width=radius*(1-.78*t**1.3)
        if ROOT_COLLAR:
            width*=1+.46*math.exp(-z/(radius*1.75))
        for column in range(COLS+1):
            u=column/COLS*2-1
            ground_curve=radius*.22*(1-u*u)*math.exp(-z/(radius*.46)) if ROOT_COLLAR else 0
            positions.append([center+width*u,-width*math.sqrt(max(0,1-u*u)),z-ground_curve])
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
    for side,boundary in zip((-1,1),root_boundaries):
        base=positions[boundary[COLS//2]]
        for row in range(1,BRANCH_ROWS+1):
            t=row/BRANCH_ROWS
            for column,index in enumerate(boundary):
                u=column/COLS*2-1
                width=radius*.925*(1-.93*t)
                start=positions[index]
                positions.append([
                    base[0]+side*(height*.11+radius*.32)*t+(start[0]-base[0])*(1-t),
                    -width*math.sqrt(1-u*u)*math.sin(t*math.pi/2),
                    base[2]*(1-t)**2-radius*.15*t+width*u,
                ])
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

root_start=branch_start+BRANCH_ROWS*(COLS+1)
branch_face_end=len(faces)
root_uv=[]
for root_index,boundary in enumerate(root_boundaries):
    coordinates={index:[col/COLS*.5,0] for col,index in enumerate(boundary)}
    root_uv.append(coordinates)
    first=root_start+root_index*BRANCH_ROWS*(COLS+1)
    for row in range(BRANCH_ROWS):
        current=list(range(first+row*(COLS+1),first+(row+1)*(COLS+1)))
        previous=boundary if row==0 else [index-COLS-1 for index in current]
        for col in range(COLS):
            pair=[(previous[col],current[col],current[col+1]),
                  (previous[col],current[col+1],previous[col+1])]
            faces.extend(face if root_index else face[::-1] for face in pair)
        for col in range(COLS+1):
            u=col/COLS*2-1
            normals.append([0,-math.sqrt(1-u*u),u])
            coordinate=[col/COLS*.5,(row+1)/BRANCH_ROWS*.55]
            coordinates[current[col]]=coordinate
            uv.append(coordinate)

root_face_end=len(faces)
additional_uv=[]
additional_boundaries=[]
if ROOT_COLLAR:
    # 左枝与前根分别从母干侧边、下缘生长，接合点沿用母干索引。
    left_boundary=[row*(COLS+1) for row in range(LAST+2,LAST+COLS+3)]
    front_boundary=list(range(2,7))
    additional_boundaries=[left_boundary,front_boundary]
    for boundary in additional_boundaries:
        first=len(poses[0])
        count=len(boundary)
        coordinates={index:[col/(count-1)*.5,0] for col,index in enumerate(boundary)}
        for row in range(1,BRANCH_ROWS+1):
            t=row/BRANCH_ROWS
            previous=boundary if row==1 else list(range(first+(row-2)*count,first+(row-1)*count))
            current=list(range(first+(row-1)*count,first+row*count))
            for col in range(count-1):
                pair=[(previous[col],current[col+1],current[col]),
                      (previous[col],previous[col+1],current[col+1])]
                faces.extend(face if boundary is left_boundary else face[::-1] for face in pair)
                additional_uv.extend([coordinates,coordinates])
            for col,index in enumerate(boundary):
                u=col/(count-1)*2-1
                normals.append([-u*.6,-math.sqrt(1-u*u*.36),0])
                coordinates[current[col]]=[col/(count-1)*.5,t*.72]
                for pose,(height,radius,length,opening) in zip(poses,parameters):
                    x,y,z=pose[index]
                    if boundary is left_boundary:
                        middle=pose[boundary[count//2]][2]
                        pose.append([x-length*.81*(.30*t+.70*t*t),
                            y-opening*.39*math.sqrt(1-u*u)*math.sin(math.pi*t),
                            middle+(z-middle)*(1-.95*t)+length*.67*t*t])
                    else:
                        pose.append([x*(1-.43*t)+radius*.26*t*t,
                            y-radius*.92*t,z-radius*(.32*t+.06*t*t+.13*t*u*u)])
        vertex_count=len(poses[0])
additional_face_end=len(faces)
plaque_uv={}
plaque_base=[]
if ROOT_COLLAR:
    # 牌底直接复用侧枝上缘的五点，木框与承托枝共用四条边。
    plaque_base=[branch_start+row*(COLS+1)+COLS for row in range(11,16)]
    top=list(range(vertex_count,vertex_count+len(plaque_base)))
    for pose,(_,_,length,_) in zip(poses,parameters):
        crown_height=pose[plaque_base[-1]][2]+.26*length
        for col,index in enumerate(plaque_base):
            x,y,z=pose[index]
            u=col/(len(plaque_base)-1)*2-1
            pose.append([x,y,crown_height-.085*length*u*u])
    for col,(bottom,upper) in enumerate(zip(plaque_base,top)):
        plaque_uv[bottom]=[col*.11,0]
        plaque_uv[upper]=[col*.11,.45]
        normals.append([0,-1,0])
    for col in range(len(plaque_base)-1):
        faces.extend([(plaque_base[col],plaque_base[col+1],top[col+1]),
                      (plaque_base[col],top[col+1],top[col])])
    vertex_count=len(poses[0])

wood_vertices=vertex_count
wood_faces=len(faces)
leaf_uv={}
if ROOT_COLLAR:
    # 图集只提供局部叶簇，各组随同一枝架顶点移动。
    donor=ROOT/'build/qa/development-tree-round2-proof'
    donor_meta=json.loads((donor/'mesh.json').read_text(encoding='utf-8'))
    patches=json.loads((donor/'result.json').read_text(encoding='utf-8'))['patches']
    donor_bytes=(donor/'mesh.bin').read_bytes()
    donor_pose=donor_meta['sections'][donor_meta['vertexPoseSections'][-1]]['offset']
    donor_corners=donor_meta['sections']['corners']
    left_start=root_start+2*BRANCH_ROWS*(COLS+1)
    attachments=[
        (ROWS*(COLS+1)+COLS//2,0,1.3,-.05),
        (branch_start+23*(COLS+1)+COLS//2,1,1.2,-.05),
        (left_start+23*(COLS+1)+COLS//2,2,1.15,-.04),
        (branch_start+17*(COLS+1)+COLS,0,.93,-.16),
        (left_start+15*(COLS+1)+COLS,1,.87,-.12),
        (48*(COLS+1)+2,2,.86,-.20),
        (54*(COLS+1)+7,1,.89,-.26),
        (branch_start+9*(COLS+1)+COLS,2,.82,-.22),
        (left_start+8*(COLS+1)+COLS,0,.94,-.16),
        (left_start+19*(COLS+1)+COLS,2,.79,-.24),
        (58*(COLS+1)+2,1,.88,-.17),
    ]
    for anchor,patch_index,size,depth in attachments:
        patch=next(p for p in patches if p['name']==f'早生叶{patch_index}')
        ox,_,oz=struct.unpack_from('<3f',donor_bytes,donor_pose+12*patch['anchorVertex'])
        start,end=patch['vertexRange']
        first=len(poses[0])
        for index in range(start,end):
            x,_,z=struct.unpack_from('<3f',donor_bytes,donor_pose+12*index)
            normals.append([0,-1,0])
            for pose,age in zip(poses,ages):
                ax,ay,az=pose[anchor]
                scale=size*(.38+2.9*age*age)
                pose.append([ax+(x-ox)*scale,ay+depth,az+(z-oz)*scale*.84])
        for offset in range(donor_corners['offset'],donor_corners['offset']+4*donor_corners['length'],36):
            values=struct.unpack_from('<9f',donor_bytes,offset)
            ids=[int(values[i]) for i in (0,3,6)]
            if all(start<=index<end for index in ids):
                face=tuple(first+index-start for index in ids)
                leaf_uv[len(faces)]={index:values[i*3+1:i*3+3] for i,index in enumerate(face)}
                faces.append(face)
    vertex_count=len(poses[0])
    shutil.copyfile(donor/'canopy.png',OUT/'canopy.png')

def face_uv(number,index):
    if number>=wood_faces:
        return leaf_uv[number][index]
    if number>=additional_face_end:
        return plaque_uv[index]
    if number>=root_face_end:
        return additional_uv[number-root_face_end][index]
    if number>=branch_face_end:
        return root_uv[(number-branch_face_end)//(BRANCH_ROWS*COLS*2)][index]
    if number>=ROWS*COLS*2:
        return child_uv[index]
    return uv[index]

payload=array('f');sections={}
def section(name,values):
    start=len(payload);payload.extend(values)
    sections[name]={'offset':start*4,'length':len(payload)-start}
section('normals',(v for p in normals for v in p))
section('corners',(v for number,face in enumerate(faces) for i in face
    for v in [i,*face_uv(number,i)]))
for index,pose in enumerate(poses):section(f'positions{index}',(v for p in pose for v in p))
frames=[]
for age,pose in zip(ages,poses):
    connection=[sum(pose[i][k] for i in base_ids)/len(base_ids) for k in range(3)]
    tip=pose[branch_start+(BRANCH_ROWS-1)*(COLS+1)+COLS//2]
    nodes=[[0,0,0],pose[ROWS*(COLS+1)+COLS//2],connection,tip]
    if ROOT_COLLAR:
        for a,b in [(top[0],top[-1]),(top[-1],top[0]),
                    (plaque_base[-1],plaque_base[0]),(plaque_base[0],plaque_base[-1])]:
            nodes.append([pose[a][axis]*.86+pose[b][axis]*.14 for axis in range(3)])
        for upper,lower in [(4,7),(5,6)]:
            a,b=nodes[upper],nodes[lower]
            nodes[upper]=[x*.89+y*.11 for x,y in zip(a,b)]
            nodes[lower]=[x*.11+y*.89 for x,y in zip(a,b)]
        # 纸面的上、下边分别保持水平，底部留出随枝倾斜的木托。
        nodes[4][2]=nodes[5][2]=min(nodes[4][2],nodes[5][2])
        nodes[6][2]=nodes[7][2]=max(nodes[6][2],nodes[7][2])
    frames.append({'age':age,'nodes':nodes,'radial':[1,1]})
metadata={'format':'共享边界局部分枝发育-v1','vertexCount':vertex_count,'triangleCount':len(faces),
    'sections':sections,'byteLength':len(payload)*4,'nodes':frames[-1]['nodes'],'edges':[[0,1],[2,3]],
    'poseFrames':frames,'vertexPoseSections':[f'positions{i}' for i in range(len(poses))],
    'samples':[{'age':age,'vertices':[{'index':i,'position':p} for i,p in enumerate(pose)]} for age,pose in zip(ages,poses)],
    'camera':{'target':[1,0,3.2],'right':[1,0,0],'up':[0,0,1],'back':[0,-1,0],'scale':8.2},
    'repeatTexture':True,'textureStyles':['wood'],'juvenileContrast':.025,'postTextureLighting':True,
    'groundShadow':False,'nearOffset':[.1,-.05],'nearSpan':[3.4,2.7],
    'scope':'仅光滑幼干、真实共享边界及首个子枝发育；没有根冠木牌，不是完整树苗或A2样件'}
if ROOT_COLLAR:
    metadata.update(format='共享枝架整树发育-v2',
        scope='共享双主枝、三粗根、枝牌与分层冠簇整树',
        textureStyles=['wood','leaf'],extraTextures=['canopy.png'],
        triangleTextures=[0]*wood_faces+[1]*(len(faces)-wood_faces),
        postTextureLighting=False,postTextureLightingMaterials=[0],
        unlitVertexStart=wood_vertices,foliageParts=len(attachments),
        plaques=[{'corners':[4,5,6,7],'title':'第一节','birth':.34,'duration':.42,'unroll':True}],
        nearOffset=[-1,-.05],nearSpan=[2.1,2.4])
    metadata['camera'].update(target=[.65,0,3.8],scale=13.3)
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
if ROOT_COLLAR:
    report['rootBoundaries']=root_boundaries
    report['additionalBoundaries']=additional_boundaries
    report['plaqueBoundary']=plaque_base
    report['woodVertices']=wood_vertices
    report['woodFaces']=wood_faces
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
if bpy is not None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh=bpy.data.meshes.new('母干共享边界与发育枝条');mesh.from_pydata(poses[-1],[],faces);mesh.update()
    obj=bpy.data.objects.new('局部分枝发育控制网格',mesh);bpy.context.collection.objects.link(obj)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable-branch.blend'))
print(json.dumps(report['mesh_export']))
