"""共享表皮的多级发育整树首套；独立预览，不引用正式页面或数据库。"""
from array import array
from collections import deque
import hashlib
import json
import math
import shutil
import sys
from pathlib import Path
import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[3]
ROUND2='--round2' in sys.argv
OUT=ROOT/('build/qa/development-tree-round2-proof' if ROUND2 else 'build/qa/development-tree-proof')
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
AGES=[0,.12,.25,.5,.75,1]
COLS=8
poses=[[] for _ in AGES];normals=[];faces=[];face_uv=[];materials=[];domains=[]
wood_parts=[];grids={};patches=[];plaques=[]
frame_nodes=[[[0,0,0],[0,0,8.2]] for _ in AGES]

def smooth(t):
    t=max(0,min(1,t));return t*t*(3-2*t)

def add_face(ids,uv,material,domain):
    faces.append(ids);face_uv.append(uv);materials.append(material);domains.append(domain)

def add_grid(name,all_points,all_normals,coordinates,parent=None,boundary=None):
    start=len(normals);first_face=len(faces);grid=[]
    for row in range(len(all_points[-1])):
        ids=[]
        for col in range(COLS+1):
            if row==0 and boundary is not None:ids.append(boundary[col]);continue
            ids.append(len(normals));normals.append(all_normals[row][col])
            for stage in range(len(AGES)):poses[stage].append(all_points[stage][row][col])
        grid.append(ids)
    for row in range(len(grid)-1):
        for col in range(COLS):
            corners=[(row,col),(row,col+1),(row+1,col+1),(row+1,col)]
            if parent is not None:corners=[corners[i] for i in [0,3,2,1]]
            for tri in [(0,1,2),(0,2,3)]:
                selected=[corners[i] for i in tri]
                add_face([grid[r][c] for r,c in selected],[coordinates[r][c] for r,c in selected],0,name)
    grids[name]=grid
    wood_parts.append({'name':name,'parent':parent,'boundary':boundary,'vertexRange':[start,len(normals)],'faceRange':[first_face,len(faces)]})

# 八个互不重叠的行窗，开口宽度随各自枝条发育，左右枝不共用同一假节点。
slots=[('根左',4,.22,.32,-1,1.55,0),('根右',14,.65,.30,1,1.8,0),
    ('下左',34,3.05,.50,-1,2.0,-.18),('下右',46,3.70,.48,1,2.2,-.15),
    ('中左',64,4.65,.36,-1,1.6,.08),('中右',76,5.25,.34,1,1.75,.10),
    ('上左',94,6.4,.23,-1,1.1,.20),('上右',106,7.0,.21,1,1.2,.22)]

def state(age,slot):
    name,_,z,opening,side,length,birth=slot
    g=smooth(age)
    life=smooth((age-birth)/.65)
    if name.startswith('根'):return .11+length*g,.03+(opening-.03)*g
    return .055+length*g*life,.015+(opening-.015)*g*life

all_points=[]
for age in AGES:
    g=smooth(age);height=(1.2+7.0*g) if ROUND2 else (1.8+6.4*g)
    knots=[(0,0),(128,height)]
    for slot in slots:
        _,row,z,_,_,_,_=slot;_,opening=state(age,slot)
        center=z*height/8.2
        knots.extend([(row,center-opening/2),(row+8,center+opening/2)])
    knots.sort();levels=np.interp(range(129),[p[0] for p in knots],[p[1] for p in knots])
    if np.any(np.diff(levels)<=0):raise RuntimeError('母干开口行高失序')
    rows=[]
    for z in levels:
        t=z/height
        width=float(np.interp(t,[0,.045,.18,.45,.75,1],[.52,.70,.49,.34,.17,.012]))*(.10+.90*g)
        center=(.10*math.sin(t*math.tau)-.20*math.sin(t*math.pi)+.06*t)*(.15+.85*g)
        if ROUND2:center=(.32*math.sin(t*math.tau)-.25*math.sin(t*math.pi)+.18*math.sin(t*math.pi*4))*(.08+.92*g)
        rows.append([[center+width*u,-width*math.sqrt(max(0,1-u*u)),
            float(z)+(.05*g*(.3+.7*math.cos(math.pi*u)**2)*math.exp(-z/.4) if ROUND2 else 0)] for u in np.linspace(-1,1,COLS+1)])
    all_points.append(rows)
normal_rows=[[[float(u),-math.sqrt(max(0,1-u*u)),0] for u in np.linspace(-1,1,COLS+1)] for _ in range(129)]
uv=[[[.18+col/COLS*.5,all_points[-1][row][col][2]*.105] for col in range(COLS+1)] for row in range(129)]
add_grid('主干',all_points,normal_rows,uv)

def branch(name,parent,first,col,lengths,rises,rows=40,has_child=False,root=False):
    parent_grid=grids[parent]
    # 母面外沿的有向边决定新表皮朝向；左枝与子枝同样使用真实边界。
    reverse=(parent=='主干' and col==0) or (parent!='主干' and col==COLS)
    boundary=[parent_grid[r][col] for r in range(first,first+9)]
    if reverse:boundary.reverse()
    if has_child:
        fractions=np.interp(range(rows+1),[0,16,24,rows],[0,.57,.63,1])
    else:fractions=np.linspace(0,1,rows+1)
    all_points=[];normal_rows=[];last_basis=None
    for stage in range(len(AGES)):
        original=np.array([poses[stage][i] for i in boundary])
        base=original.mean(axis=0);direction=original[-1]-original[0]
        opening=math.hypot(direction[0],direction[2]);d=np.array([direction[0]/opening,0,direction[2]/opening]);out=np.array([d[2],0,-d[0]])
        length=lengths[stage]
        rise=(.055-base[2]-out[2]*length)/d[2] if root else rises[stage]*length
        points=[original.tolist()]
        for t in fractions[1:]:
            reach=.10*t+.90*t*t;slope=2*(rise/length)*t*t;factor=math.sqrt(1+slope*slope)
            normal=(-out*slope+d)/factor
            width=opening*.5*(1-(.82 if root else .97)*t)
            blend=smooth(t*5);line=[]
            for column,u in enumerate(np.linspace(-1,1,COLS+1)):
                correction=(original[column]-base-d*opening*.5*u)*(1-blend)
                p=base+out*length*reach+d*rise*t*t*t+normal*width*u+correction
                p[1]=base[1]-width*math.sqrt(max(0,1-u*u))
                if root and t==1:p+=(out+d*slope)/factor*width*.55*math.sqrt(max(0,1-u*u))
                if root and ROUND2:
                    # 下沿较早接地，上沿形成宽厚根趾，末端保持圆钝，不把侧根作为悬臂。
                    g=smooth(AGES[stage]);low=float(original[:,2].min());high=float(original[:,2].max())
                    lower=.003+.002*g+(low-.003-.002*g)*(1-t)**4
                    upper=.014+.031*g+(high-.014-.031*g)*(1-t)**1.5
                    v=column/COLS if d[2]>0 else 1-column/COLS
                    residual_z=original[column][2]-(low+(high-low)*v)
                    p[0]=base[0]+out[0]*length*t+(original[column][0]-base[0])*(1-blend)
                    p[2]=lower+(upper-lower)*v+residual_z*(1-blend)
                    p[1]=base[1]-(upper-lower)*.5*math.sqrt(max(0,1-u*u))
                    if t==1:p[0]+=out[0]*(upper-lower)*.28*math.sqrt(max(0,1-u*u))
                line.append(p.tolist())
            points.append(line)
        all_points.append(points);last_basis=(d,out,opening,rise/length)
    d,out,opening,k=last_basis
    normal_rows=[[normals[i] for i in boundary]]
    for t in fractions[1:]:
        blend=smooth(t*5);n=(-out*2*k*t*t+d)/math.sqrt(1+(2*k*t*t)**2);line=[]
        for column,u in enumerate(np.linspace(-1,1,COLS+1)):
            target=n*u
            if root and ROUND2:target=np.array([0,0,float(np.sign(d[2]))])*u
            target[1]=-math.sqrt(max(0,1-u*u))
            line.append((np.array(normals[boundary[column]])*(1-blend)+target*blend).tolist())
        normal_rows.append(line)
    phase=(len(wood_parts)%4)*.06
    uv=[[[phase+col/COLS*.5,.12+lengths[-1]*(.10*t+.90*t*t)*.22] for col in range(COLS+1)] for t in fractions]
    add_grid(name,all_points,normal_rows,uv,parent,boundary)

for slot in slots:
    name,row,_,_,side,_,_=slot
    branch(name,'主干',row,0 if side<0 else COLS,[state(a,slot)[0] for a in AGES],[(side if ROUND2 else -side)*.36]*len(AGES),root=name.startswith('根'),has_child=not name.startswith('根'))
for name in ['下左','下右','中左','中右','上左','上右']:
    side=-1 if name.endswith('左') else 1
    length=.80 if name.startswith('上') else 1.05
    branch(name+'次枝',name,16,0 if side<0 else COLS,[.055+length*smooth(a)*smooth((a-.18)/.6) for a in AGES],[.75 if side<0 else -.75]*len(AGES),rows=24)
wood_count=len(normals)

source_dir=ROOT/'assets/source/magic_tree/textures_source'
source_paths=[source_dir/'development_bark_v1.png',source_dir/'reference_canopy_v1.png',source_dir/'reference_frames_v1.png']
images=[bpy.data.images.load(str(p)) for p in source_paths];alpha=[]
for image in images:
    values=np.empty(image.size[0]*image.size[1]*4,dtype=np.float32);image.pixels.foreach_get(values)
    if image==images[0] and np.any(values.reshape(-1,4)[:,3]<.99999):raise RuntimeError('后置明暗只允许完全不透明表皮')
    alpha.append(values.reshape(image.size[1],image.size[0],4)[::-1,:,3]>.5)
analysis=json.loads((ROOT/'build/qa/reference-canopy-analysis/components.json').read_text(encoding='utf-8'))
if analysis['sha256']!=hashlib.sha256(source_paths[1].read_bytes()).hexdigest():raise RuntimeError('冠簇标签过期')
labels=np.frombuffer((ROOT/'build/qa/reference-canopy-analysis/labels.bin').read_bytes(),dtype='<u4').reshape(analysis['height'],analysis['width'])

def opaque_near(mask,p):
    yy,xx=np.where(mask);distance=(xx-p[0])**2+(yy-p[1])**2;i=int(distance.argmin())
    if distance[i]>60**2:raise RuntimeError('素材基点不在设计位置附近')
    return (int(xx[i]),int(yy[i]))

def patch(name,material,selection,base,anchor,scale,birth=.10,early=False,paper=None,aperture=None):
    if not alpha[material][base[1],base[0]]:raise RuntimeError('子素材基点非实体')
    yy,xx=np.where(selection);xa=max(0,int(xx.min())-3);xb=min(selection.shape[1]-1,int(xx.max())+3)
    ya=max(0,int(yy.min())-3);yb=min(selection.shape[0]-1,int(yy.max())+3)
    first=len(normals);rows=12
    growth=[.8+.2*smooth(a) if early else .003+.997*smooth((a-birth)/(.45 if ROUND2 else .65)) for a in AGES]
    def position(stage,x,y):
        p=poses[stage][anchor];front=.0
        if material==2:front=min(1,abs(x-base[0])/240)
        depth=.012-.065*front if material==2 else -.015-.002*len(patches)
        return [p[0]+(x-base[0])*scale*growth[stage],p[1]+depth,p[2]+(base[1]-y)*scale*growth[stage]]
    for row in range(rows+1):
        for col in range(rows+1):
            x=xa+(xb-xa)*col/rows;y=ya+(yb-ya)*row/rows
            normals.append([0,-1,0])
            for stage in range(len(AGES)):poses[stage].append(position(stage,x,y))
    for row in range(rows):
        for col in range(rows):
            x=int(xa+(xb-xa)*col/rows);xx=int(xa+(xb-xa)*(col+1)/rows)+1
            y=int(ya+(yb-ya)*row/rows);yy=int(ya+(yb-ya)*(row+1)/rows)+1
            if not selection[y:yy,x:xx].any():continue
            a=first+row*(rows+1)+col
            for ids in [(a,a+rows+1,a+rows+2),(a,a+rows+2,a+1)]:
                uv=[]
                for i in ids:
                    local=i-first;r=local//(rows+1);c=local%(rows+1)
                    uv.append([(xa+(xb-xa)*c/rows)/images[material].size[0],1-(ya+(yb-ya)*r/rows)/images[material].size[1]])
                add_face(ids,uv,material,name)
    patches.append({'name':name,'material':material,'anchorVertex':anchor,'baseSource':base,'vertexRange':[first,len(normals)]})
    if paper:
        ids=[]
        for x,y in paper:
            ids.append(len(frame_nodes[0]))
            for stage in range(len(AGES)):frame_nodes[stage].append(position(stage,x,y))
        plaques.append({'corners':ids,'title':'第九章' if name=='左章牌' else '第一节','birth':.18,'duration':.46,'unroll':True,'inset':1,'aperture':aperture})

def tip(name):return grids[name][-1][COLS//2]
canopies=[(2,(275,351),tip('主干'),.006),
    (1,(776,350),tip('上左'),.006),(3,(880,345),tip('上右'),.006),
    (5,(220,750),grids['主干'][94][COLS//2],.006),
    (7,(749,735),tip('中左'),.006),(6,(888,730),tip('中右'),.006),
    (9,(370,1135),tip('下左'),.006),(8,(480,1127),tip('下右'),.006),
    (10,(897,1120),tip('中右次枝'),.0045)]
if ROUND2:
    canopies=[(2,(275,351),grids['主干'][122][COLS//2],.006),
        (1,(776,350),grids['上左'][26][COLS//2],.006),(3,(880,345),grids['上右'][26][COLS//2],.006),
        (5,(220,750),grids['主干'][88][COLS//2],.006),
        (7,(749,735),grids['中左'][26][COLS//2],.006),(6,(888,730),grids['中右'][26][COLS//2],.006),
        (9,(370,1135),grids['下左'][26][COLS//2],.006),(8,(480,1127),grids['下右'][26][COLS//2],.006),
        (10,(897,1120),grids['中右次枝'][19][COLS//2],.0045)]
for i,(component,base,anchor,scale) in enumerate(canopies):
    selection=labels==component
    patch(f'C{i+1}',1,selection,opaque_near(selection,base),anchor,scale,birth=.10+.025*(i%3))
if ROUND2:
    for name in ['下左','下右','中左','中右','上左','上右']:
        component,base=(1,(776,350)) if name.endswith('左') else (3,(880,345))
        selection=labels==component
        patch(name+'次枝展叶',1,selection,opaque_near(selection,base),grids[name+'次枝'][19][COLS//2],.0035,birth=.12)
for i,(component,base,anchor) in enumerate([(9,(370,1135),tip('上左') if ROUND2 else tip('下左')),(3,(880,345),tip('上右') if ROUND2 else tip('下右')),(2,(275,351),tip('主干'))]):
    selection=labels==component
    patch(f'早生叶{i}',1,selection,opaque_near(selection,base),anchor,.0015,early=True)

def aperture(seed):
    queue=deque([seed]);seen={seed};lines={}
    while queue:
        x,y=queue.popleft()
        if x in (0,alpha[2].shape[1]-1) or y in (0,alpha[2].shape[0]-1):raise RuntimeError('木牌空窗未闭合')
        lines.setdefault(y,[]).append(x)
        for p in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
            if p not in seen and not alpha[2][p[1],p[0]]:seen.add(p);queue.append(p)
    ys=sorted(lines);outline=[(min(lines[y]),y) for y in ys]+[(max(lines[y])+1,y+1) for y in reversed(ys)]
    xa=min(x for x,y in outline);xb=max(x for x,y in outline);ya=min(y for x,y in outline);yb=max(y for x,y in outline)
    return [(xa,ya),(xb,ya),(xb,yb),(xa,yb)],[[(x-xa)/(xb-xa),(y-ya)/(yb-ya)] for x,y in outline]
for name,base,seed,anchor in [('左章牌',(710,725),(319,399),grids['主干'][27 if ROUND2 else 31][0]),('右节牌',(1060,725),(1437,399),grids['主干'][28 if ROUND2 else 32][COLS])]:
    selection=alpha[2].copy()
    if name=='左章牌':selection[:,887:]=False
    else:selection[:,:887]=False
    paper,outline=aperture(seed)
    patch(name,2,selection,opaque_near(selection,base),anchor,.0023,birth=.10,paper=paper,aperture=outline)

payload=array('f');sections={}
def section(name,values):
    start=len(payload);payload.extend(values);sections[name]={'offset':start*4,'length':len(payload)-start}
section('normals',(v for p in normals for v in p))
section('corners',(v for ids,uv in zip(faces,face_uv) for i,coordinate in zip(ids,uv) for v in [i,*coordinate]))
for i,pose in enumerate(poses):section(f'positions{i}',(v for p in pose for v in p))
frame_points=[poses[-1][i] for p in patches if p['material']==2 for i in range(*p['vertexRange'])]
left=min(p[0] for p in frame_points);right=max(p[0] for p in frame_points);bottom=min(p[2] for p in frame_points);top=max(p[2] for p in frame_points)
metadata={'format':'多级共享表皮发育整树-v1','vertexCount':len(normals),'triangleCount':len(faces),'sections':sections,'byteLength':len(payload)*4,
    'nodes':frame_nodes[-1],'edges':[[0,1]],'poseFrames':[{'age':a,'nodes':frame_nodes[i],'radial':[1]} for i,a in enumerate(AGES)],
    'vertexPoseSections':[f'positions{i}' for i in range(len(AGES))],
    'samples':[{'age':a,'vertices':[{'index':i,'position':p} for i,p in enumerate(poses[s])]} for s,a in enumerate(AGES)],
    'camera':{'target':[0,0,4.8],'right':[1,0,0],'up':[0,0,1],'back':[0,-1,0],'scale':12.4},
    'repeatTexture':True,'extraTextures':['canopy.png','frames.png'],'triangleTextures':materials,'textureStyles':['wood','leaf','frame'],
    'postTextureLightingMaterials':[0],'unlitVertexStart':wood_count,'juvenileContrast':.04,
    'groundShadow':True,'rootWidth':[.10,.55,1],'foliageParts':sum(p['material']==1 for p in patches),'plaques':plaques,
    'nearSpan':[(right-left)*1.08,(top-bottom)*1.15],'nearOffset':[-(left+right)/2,(top+bottom)/2-4.8],
    'scope':'多级共享表皮发育完整第二套，最后一次整体修改' if ROUND2 else '多级共享表皮发育完整首套，待四图短片整体审查'}
(OUT/'mesh.bin').write_bytes(payload.tobytes());(OUT/'mesh.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
for source,name in zip(source_paths,['baked-bark.png','canopy.png','frames.png']):shutil.copyfile(source,OUT/name)
report={'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'sourceImages':[{'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in source_paths],
    'mesh_export':{'vertices':len(normals),'triangles':len(faces),'bytes':len(payload)*4,'referenceSamples':len(normals)*len(AGES)},
    'woodVertexCount':wood_count,'woodParts':wood_parts,'triangleDomains':domains,'patches':patches,'foliageParts':metadata['foliageParts'],
    'production_integrated':False,'visualAcceptance':'完整第二套，待实际四图短片整体审查' if ROUND2 else '新完整造型首套，待实际四图短片整体审查'}
(OUT/'result.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
mesh=bpy.data.meshes.new('多级共享表皮发育整树');mesh.from_pydata(poses[-1],[],faces);mesh.update()
obj=bpy.data.objects.new('独立发育整树首套',mesh);bpy.context.collection.objects.link(obj)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'editable-tree.blend'))
print(json.dumps(report['mesh_export']))
